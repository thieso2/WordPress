# frozen_string_literal: true

module Publishing
  # AGG-Post — the aggregate root. target_domain_model.md § AGG-Post.
  #
  # AD-02: STI over CONTENT types only. `post_type` in the legacy encoded two
  # unrelated things — a content subtype (post, page: same shape, same lifecycle,
  # same queries) and storage tenancy (eleven unrelated things sharing a table
  # because WordPress had one flexible table and no migrations). Only the first is
  # inheritance, and only the first lives here.
  #
  # AD-01: there is no hook system. Every rule below is WordPress's *unfiltered
  # default*, and here that default is the permanent, only behaviour. Nothing can
  # change it at runtime — which is what makes it testable against the oracle.
  #
  # ── Accepted commands (target_domain_model.md § AGG-Post) ─────────────────────
  #   create     → ActiveRecord `create!` (wp_insert_post, post.php:4598)
  #   update     → ActiveRecord `update!` (wp_update_post, post.php:5327); every update
  #                records a revision when anything revisioned changed — `revise!`
  #   publish    → `publish!`       schedule → `schedule!`     unpublish → `unpublish!`
  #   trash      → `trash!`         restore  → `restore!`      delete    → `delete!`
  #   revise     → `revise!` / `autosave!`
  # Each was run against the live oracle and the resulting row state compared:
  # spec/models/publishing/commands_differential_spec.rb.
  #
  # The actor performing a command travels EXPLICITLY (`actor:`), never through a global
  # (paradigm_decision.md implication 1; the legacy read get_current_user_id()).
  class Post < ApplicationRecord
    self.table_name = "posts"

    # AD-03's residual bucket: genuinely arbitrary metadata, after every core-owned
    # postmeta key was promoted to a real column, association or table. jsonb with a
    # GIN index — the legacy left meta_value unindexed in all six meta tables and it is
    # the dominant slow-query source (F-DD-02, TD-07).
    #
    # ⚠️ target_data_model.md names this column `attributes`; it is
    # `residual_attributes` here because Active Record cannot map the specified name.
    # See db/migrate/20260822000011 and README § Schema deviations.

    STATUSES = %w[auto_draft draft pending scheduled published private trashed].freeze

    # BR-MIGRATE-032: slugs are not allocated for these statuses. The legacy expresses
    # this by leaving post_name = '' — and `posts.slug` is NULL here instead, which is
    # load-bearing: reproducing NOT NULL DEFAULT '' would collide every draft against
    # every other in the unique index. The partial index WHERE slug IS NOT NULL is what
    # makes the constraint expressible at all. (handoff.md, "Six things", item 1)
    SLUGLESS_STATUSES = %w[auto_draft draft pending].freeze

    # BR-MIGRATE-029 / BR-MIGRATE-030 (legacy BR-POST-01/02, wp-includes/post.php:4800).
    # A publish request whose published_at is at least this far in the future becomes
    # `scheduled`; one closer than this becomes `published`. Confirmed by the owner as
    # intended product behaviour, not an implementation accident — so it is a named
    # model rule here rather than a side effect of a date comparison.
    SCHEDULING_THRESHOLD = 60.seconds

    # wp_check_post_lock_window (wp-admin/includes/post.php:1737): the number of seconds a
    # post lock stays live after its last heartbeat. `apply_filters( 'wp_check_post_lock_
    # window', 150 )`, unfiltered under AD-01 — so 150 s, permanently. A lock older than
    # this is ignored and silently overwritten by the next editor to open the post.
    LOCK_WINDOW = 150.seconds

    # BR-MIGRATE-035: 200 bytes INCLUDING any numeric suffix. Bytes, not characters —
    # the corpus carries 4-byte UTF-8, where the difference is a factor of four.
    SLUG_MAX_BYTES = 200

    # wp_revisions_to_keep() (wp-includes/revision.php:812) with WP_POST_REVISIONS at
    # its default `true`: -1, unlimited. Confirmed on the oracle. AD-01: the
    # `wp_revisions_to_keep` and `wp_{type}_revisions_to_keep` filters are gone, so this
    # is the only value. 0 would disable revisions (wp_revisions_enabled, :795).
    REVISIONS_TO_KEEP = -1

    # `scopes: false`: one of the legacy's seven statuses is `private`, and a generated
    # `Post.private` class scope would collide with Ruby's own `private`. The predicate
    # methods (`post.private?`) are unaffected; the scopes are declared by hand below.
    enum :status, STATUSES.index_with(&:itself), validate: true, scopes: false
    enum :status_before_trash, STATUSES.index_with(&:itself),
         prefix: :before_trash, validate: { allow_nil: true }, scopes: false

    belongs_to :author, class_name: "Identity::User", optional: true
    belongs_to :parent, class_name: "Publishing::Post", optional: true
    belongs_to :featured_asset, class_name: "Library::Asset", optional: true
    # The editor's lock holder — the `_edit_lock`/`_edit_last` user, promoted to a column
    # (AD-03, db/migrate/20260823000300). See `edit_lock_holder_if_live` and friends below.
    belongs_to :edit_lock_holder, class_name: "Identity::User", foreign_key: :edit_lock_by_id, optional: true
    # No `dependent:` — wp_delete_post() REPARENTS children to the deleted record's own
    # parent (post.php:3893, `$parent_data = array( 'post_parent' => $post->post_parent )`)
    # rather than deleting them; see `reparent_children`. The FK's ON DELETE CASCADE is
    # the floor beneath a raw DELETE, not the behaviour of the command.
    has_many :children, class_name: "Publishing::Post", foreign_key: :parent_id
    has_many :revisions, class_name: "Publishing::Revision", dependent: :destroy
    has_many :post_attributes, class_name: "Publishing::Attribute", dependent: :destroy
    has_many :status_transitions, class_name: "Publishing::StatusTransition", dependent: :destroy

    # The user performing the current command. Explicit, per call, never ambient.
    attr_accessor :actor

    validates :title, :content, :excerpt, exclusion: { in: [nil] }
    validate :slug_within_byte_budget
    validate :slug_is_not_a_reserved_segment
    validate :trash_state_is_all_or_nothing

    before_validation :resolve_scheduled_status
    before_validation :allocate_slug_when_required
    before_save :stamp_modified_at
    before_destroy :reparent_children
    after_save :record_status_transition
    after_update :record_revision
    after_update :announce_slug_change

    STATUSES.each { |s| scope :"in_#{s}", -> { where(status: s) } }
    scope :published, -> { where(status: :published) }
    scope :visible, -> { where(status: %i[published private]) }
    # RISK-007: MySQL and PostgreSQL disagree on the default null ordering, so
    # NULLS LAST is stated explicitly wherever ordering matters. Every draft carries
    # a NULL published_at (it carried '0000-00-00 00:00:00' in the legacy).
    scope :newest_first, -> { order(Arel.sql("published_at DESC NULLS LAST, id DESC")) }

    # The scheduled work that is due. What the legacy could only learn by reading the
    # `cron` option (F-CRON-03) is a query on the record itself here, so it cannot be
    # lost to the settings store (AD-06, feature 12 COUPLING 3).
    scope :due_for_publication, ->(now = Time.current) { in_scheduled.where(published_at: ..now) }

    # Hierarchical types allocate slugs unique within (type, parent); flat types
    # within (type). BR-MIGRATE-033. Subclasses override.
    def self.hierarchical? = false

    def hierarchical? = self.class.hierarchical?

    def slug_required? = !SLUGLESS_STATUSES.include?(status.to_s)

    # wp_revisions_enabled(), revision.php:795.
    def self.revisions_enabled? = REVISIONS_TO_KEEP != 0

    # ── Commands ──────────────────────────────────────────────────────────────────

    # AGG-Post accepted command `publish`. BR-MIGRATE-029/030 decide which status
    # results: the verb asks for publication, the DATE decides whether it is immediate.
    # A first publication allocates the slug (BR-MIGRATE-032, post.php:5047) through
    # the Routing-supplied port — see `allocate_slug_when_required`.
    #
    # With no `at:`, an instant the record ALREADY carries is kept: wp_insert_post()
    # (post.php:4748) takes the date from the merged row on update and stamps "now" only
    # when it is empty/zero, so a draft that was published before and unpublished
    # (`unpublish!` retains the instant) republishes on its ORIGINAL date. Verified on the
    # oracle (commands_differential_spec, "republish").
    def publish!(at: nil, actor: self.actor)
      self.actor = actor
      self.published_at = at || published_at || Time.current
      self.status = scheduled_relative_to?(at) ? :scheduled : :published
      save!
    end

    # AGG-Post accepted command `schedule`. The legacy has no scheduling verb: a
    # publication with a date ≥ 60 s ahead IS a schedule (post.php:4800), and one closer
    # than that publishes now (BR-MIGRATE-030). The rule is the same rule; the verb is
    # the caller's intent, and the threshold — not the verb — decides.
    def schedule!(at:, actor: self.actor)
      publish!(at: at, actor: actor)
    end

    # AGG-Post accepted command `unpublish`: back to draft. Verified on the oracle
    # (wp_update_post with post_status = 'draft'): the slug and the publication instant
    # are RETAINED — post.php:4745 regenerates a slug only when it is empty, and the date
    # is left alone — while the classification counts fall to zero (BR-TAX-11), which is
    # the cascade feature 12 COUPLING 1 pins down. A trashed record is restored first.
    def unpublish!(actor: self.actor)
      self.actor = actor
      transaction do
        restore! if trashed?
        update!(status: :draft)
      end
    end

    # AGG-Post accepted command `trash` (wp_trash_post, post.php:4084). The prior
    # status and the instant go into columns the legacy kept as `_wp_trash_meta_status`
    # / `_wp_trash_meta_time` postmeta (AD-03).
    def trash!(actor: self.actor)
      return true if trashed?

      self.actor = actor
      transaction do
        update!(status_before_trash: status, trashed_at: Time.current, status: :trashed)
      end
    end

    # AGG-Post accepted command `restore` (wp_untrash_post, post.php:4168). Restoring
    # returns the PRIOR status — target_domain_model.md § AGG-Post, and PT-001 "Trash
    # state is all-or-nothing and restores the prior status".
    #
    # ⚠️ Recorded divergence from the unfiltered legacy default. Since 5.6.0 the legacy
    # restores to 'draft' (post.php:4210, `$new_status = 'draft'`) unless the
    # `wp_untrash_post_status` filter — for which core ships
    # wp_untrash_post_set_previous_status() but does NOT register it — says otherwise.
    # Confirmed on the oracle: trash a published record, untrash, status = 'draft'. The
    # specification chose the pre-5.6 behaviour deliberately (it is what the columns
    # exist for), so that is what this does; see the parity report.
    def restore!(actor: self.actor)
      return true unless trashed?

      self.actor = actor
      transaction do
        update!(status: status_before_trash, status_before_trash: nil, trashed_at: nil)
      end
    end

    # AGG-Post accepted command `delete` (wp_delete_post with $force_delete, post.php:
    # 3834). Verified on the oracle: revisions, comments, attributes and classification
    # assignments go with the record; CHILDREN are reparented to the record's own parent
    # (`reparent_children`); attachments are detached (db/migrate/20260822000061).
    # Revisions, attributes and transitions go by FK cascade and `dependent: :destroy`
    # alike; comments by Discussion's FK; assignments by the Classification trigger.
    def delete!(actor: self.actor)
      self.actor = actor
      destroy!
    end

    # AGG-Post accepted command `revise` — wp_save_post_revision(), revision.php:130.
    # Records the record AS IT NOW STANDS, unless nothing revisioned changed since the
    # latest non-autosave revision. Runs after every update (`record_revision`), as the
    # legacy runs it on `post_updated`; callable directly for an explicit snapshot.
    #
    # Verified on the oracle, in order:
    #   * the first update after creation always records one (":178, If no previous
    #     revisions, save one") — even a status-only publish;
    #   * an update changing no revisioned field records none;
    #   * a whitespace-only change records none (normalize_whitespace, :190);
    #   * a title change records one; the copy is of the NEW state.
    # AD-01: `wp_save_post_revision_check_for_changes` and
    # `wp_save_post_revision_post_has_changed` are gone; the comparison is the rule.
    #
    # Returns the revision, or nil when none was due.
    def revise!(actor: self.actor)
      return nil if auto_draft?                      # revision.php:152
      return nil unless self.class.revisions_enabled?

      latest = revisions.regular.newest_first.first
      return nil if latest && !latest.differs_from?(self)

      revision = revisions.create!(
        author: actor, title: title, content: content, excerpt: excerpt,
        autosave: false, created_at: modified_at || Time.current
      )
      prune_revisions!
      revision
    end

    # The autosave half of `revise` — wp_create_post_autosave(), wp-admin/includes/
    # post.php:1957. ONE autosave per author, overwritten in place; an autosave whose
    # fields equal the record's current fields is DELETED instead (":1982, If the new
    # autosave has the same content as the post, delete the autosave") and nil is
    # returned. Verified on the oracle: two autosaves by one author share one id; a
    # third identical to the record removes it.
    #
    # With no actor, the legacy's `wp_get_post_autosave( $id, 0 )` matches any author's
    # autosave; the same is done here.
    def autosave!(title:, content:, excerpt: "", actor: self.actor)
      data = { title: title.to_s, content: content.to_s, excerpt: excerpt.to_s }
      existing = revisions.autosaves
      existing = existing.where(author_id: actor.id) if actor
      existing = existing.newest_first.first

      return revisions.create!(data.merge(author: actor, autosave: true, created_at: Time.current)) if existing.nil?

      same_as_record = Publishing::Revision::FIELDS.none? do |field|
        Publishing::Revision.normalize_whitespace(data[field.to_sym]) !=
          Publishing::Revision.normalize_whitespace(public_send(field))
      end
      if same_as_record
        existing.destroy!
        nil
      else
        existing.update!(data.merge(author: actor || existing.author, created_at: Time.current))
        existing
      end
    end

    # check_and_publish_future_post(), post.php:5482 — what the `publish_future_post`
    # cron event does when it fires. A record that is no longer scheduled is left alone
    # (the BR-MIGRATE-038 guard); one whose instant has not arrived is re-armed; one that
    # is due is published with its date UNCHANGED (wp_publish_post, :5404, writes only
    # post_status). Returns true when it published.
    def publish_due!(now: Time.current)
      return false unless scheduled?

      if published_at > now
        Publishing::PublishScheduledJob.set(wait_until: published_at).perform_later(id)
        return false
      end

      update!(status: :published)
      true
    end

    # ── Post locking (the editor) ────────────────────────────────────────────────
    #
    # wp_set_post_lock (wp-admin/includes/post.php:1760): stamp "<now>:<actor>". Also the
    # take-over path — post.php's `get-post-lock` handler simply calls wp_set_post_lock()
    # for the arriving user, so acquiring, refreshing (the heartbeat) and stealing are the
    # same write. Returns [time, user] as the legacy does, or false with no actor (:1767).
    #
    # `update_columns`: a lock is not an edit. The legacy wrote postmeta, which never
    # touched post_modified and never triggered `post_updated` — so locking here must not
    # bump modified_at or record a revision. It writes the two columns and nothing else.
    def lock_editing!(actor:)
      return false if actor.nil?

      now = Time.current
      update_columns(edit_lock_at: now, edit_lock_by_id: actor.id)
      [now, actor]
    end
    alias_method :steal_lock!, :lock_editing!

    # wp_check_post_lock (wp-admin/includes/post.php:1715): the user CURRENTLY holding a
    # live lock, from the point of view of `actor`. A lock is live when its timestamp is
    # within LOCK_WINDOW of now (:1739) and its holder still exists (:1732); it is
    # reported only when that holder is someone OTHER than the asking actor (:1739,
    # `get_current_user_id() !== $user`). Otherwise nil — the post is editable.
    def edit_lock_holder_if_live(actor:, now: Time.current)
      return nil if edit_lock_at.nil? || edit_lock_by_id.nil?
      return nil unless edit_lock_at > now - LOCK_WINDOW
      return nil if actor && actor.id == edit_lock_by_id

      edit_lock_holder
    end

    # Whether the post is locked against `actor` right now — the guard the editor consults
    # before letting an edit through.
    def locked_against?(actor, now: Time.current)
      edit_lock_holder_if_live(actor: actor, now: now).present?
    end

    # A target nicety, not a legacy behaviour: the legacy never cleared `_edit_lock`, it
    # let the 150 s window expire. Clearing on an explicit "leave the editor" makes the
    # post immediately editable elsewhere, which is strictly friendlier and observably
    # identical once the window has passed. Only the holder may release.
    def release_lock!(actor:)
      return false if actor.nil? || edit_lock_by_id != actor.id

      update_columns(edit_lock_at: nil, edit_lock_by_id: nil)
      true
    end

    private

    def scheduled_relative_to?(instant)
      instant.present? && instant >= Time.current + SCHEDULING_THRESHOLD
    end

    # BR-MIGRATE-029/030. The legacy performs this silently inside wp_insert_post(), so
    # a caller cannot set status independently of date; that coupling is preserved
    # deliberately, as a named rule rather than as an inline date comparison.
    def resolve_scheduled_status
      return unless published_at.present?
      return unless status.to_s.in?(%w[published scheduled])

      self.status = scheduled_relative_to?(published_at) ? "scheduled" : "published"
    end

    # BR-MIGRATE-032 (post.php:5047): a record leaving the slugless statuses with no
    # slug gets one derived from its title — unique within its scope and clear of the
    # reserved set, which only Routing can guarantee (BR-MIGRATE-033/034), hence the
    # port. A draft keeps NULL; a record that already has a slug keeps it.
    def allocate_slug_when_required
      return if slug.present? || !slug_required?

      self.slug = Publishing.slug_allocator.call(self, nil).presence
    end

    def stamp_modified_at
      self.modified_at = Time.current if changed?
    end

    # wp_delete_post(), post.php:3893: children of the same type move up to the deleted
    # record's parent. A raw DELETE still cascades through the FK; this command does
    # not. A child whose slug collides with a new sibling is refused by the unique index
    # (AD-05) — the legacy, having no index, would silently keep the duplicate.
    def reparent_children
      self.class.where(parent_id: id, type: type).update_all(parent_id: parent_id)
    end

    # BR-MIGRATE-036: every status change is recorded as a StatusTransition.
    # AD-01 again: the legacy fired the `transition_post_status` action here. A
    # broadcast is not readable at the call site, so the target records a row instead
    # — queryable, and with no way for anything to observe it and change the outcome.
    #
    # A transition INTO `scheduled` arms the publication job, as `_future_post_hook()`
    # (post.php:8177) armed the `publish_future_post` cron event. BR-MIGRATE-038's
    # "clear on every transition" is unnecessary here: `publish_due!` checks the status
    # when the job runs, so a stale job is a no-op.
    def record_status_transition
      previous, current = saved_change_to_status
      return if previous == current

      status_transitions.create!(from_status: previous, to_status: current,
                                 actor_id: actor&.id, occurred_at: Time.current)
      return unless current.to_s == "scheduled"

      Publishing::PublishScheduledJob.set(wait_until: published_at).perform_later(id)
    end

    # `post_updated` -> wp_save_post_revision (default-filters.php). Every update, not
    # only content edits: the oracle records the first revision at a status-only publish.
    def record_revision
      revise!
    end

    # wp_check_for_changed_slugs(), post.php:7567: published, non-hierarchical, slug
    # actually changed, old slug non-empty. What to DO about it belongs to Routing.
    def announce_slug_change
      previous, current = saved_change_to_slug
      return if previous.blank? || previous == current
      return unless published? && !hierarchical?

      Publishing.slug_change_recorder.call(self, previous)
    end

    # wp_save_post_revision(), revision.php:223-270: with a non-negative limit, the
    # oldest non-autosave revisions beyond it are deleted. Never runs at the default -1.
    def prune_revisions!
      return if REVISIONS_TO_KEEP.negative?

      all = revisions.oldest_first.to_a
      excess = all.length - REVISIONS_TO_KEEP
      return if excess < 1

      all.first(excess).reject(&:autosave).each(&:destroy!)
    end

    def slug_within_byte_budget
      return if slug.blank?
      return if slug.bytesize <= SLUG_MAX_BYTES

      errors.add(:slug, "exceeds #{SLUG_MAX_BYTES} bytes including any numeric suffix")
    end

    # BR-MIGRATE-034: a slug may not collide with a reserved route segment, "because
    # only Routing knows the reserved set".
    #
    # ⚠️ Modelled deliberately, and this is the one place in the core where that
    # matters. migration_strategy.md § Sequencing records rewrite <-> query as the one
    # cycle edge that "survives genuinely": routing configuration constrains slug
    # validation, and Routing already depends on Publishing (Routing::Redirect carries
    # a post_id). Calling Routing from here would close that loop, and under topology
    # option 3 nothing but bin/check_cycles would notice.
    #
    # So the dependency is inverted: Publishing owns the *interface* and Routing
    # supplies the implementation at boot (config/initializers/reserved_segments.rb).
    # The arrow stays Routing -> Publishing and the graph stays a DAG.
    def slug_is_not_a_reserved_segment
      return if slug.blank?
      return unless Publishing.reserved_segments.include?(slug)

      errors.add(:slug, "collides with a reserved route segment")
    end

    def trash_state_is_all_or_nothing
      return if trashed_at.nil? == status_before_trash.nil?

      errors.add(:base, "trashed_at and status_before_trash are set together or not at all")
    end
  end
end
