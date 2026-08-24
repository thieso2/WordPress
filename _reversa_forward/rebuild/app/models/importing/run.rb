# frozen_string_literal: true

module Importing
  # The WXR importer — console.import. Takes an Importing::Wxr::Document and maps it onto
  # the real aggregates through their own commands, exactly as lib/seeding/pipeline.rb
  # maps the oracle's MySQL onto them: NOT raw SQL, because "routing the load through the
  # models means every CHECK, unique index, FK and validation in target_data_model.md is
  # exercised by the load itself." The importer is therefore also a test of the schema.
  #
  # ── Conventions carried over from Seeding::Pipeline, deliberately ─────────────────
  #  · ID REMAPPING. A WXR carries the SOURCE site's ids (wp:post_id, wp:comment_id,
  #    wp:term_id, wp:author_id) and points at them from wp:post_parent,
  #    wp:comment_parent and wp:comment_user_id. `posts.id` is GENERATED ALWAYS AS
  #    IDENTITY here, so those ids cannot be preserved even in principle — every
  #    relationship is rebuilt through `@map`, one hash per source table, exactly as the
  #    pipeline does. This is the single largest source of silent corruption in a naive
  #    importer and it is the reason both halves are written the same way.
  #  · TWO PASSES over anything self-referential (post_parent, term_parent,
  #    comment_parent), then a forced-root pass for the leftovers — the pipeline's shape,
  #    because a WXR is emitted in query order and a child may precede its parent.
  #  · A DEAD-LETTER DISCIPLINE. A record that cannot be mapped is REPORTED, never
  #    coerced into a default (Importing::Result).
  #  · AD-07: the *_gmt column is the source of truth for every timestamp; the local
  #    column is discarded because it is derivable from the site timezone.
  #  · T-01 / T-05 / T-07 / T-08 / T-10 are literally the same functions
  #    (Seeding::Transformations), so the two loaders cannot drift on what a zero date,
  #    an unmapped comment_approved or a guid means.
  #
  # ── What this importer does NOT do, and says so on the screen ────────────────────
  #  · ATTACHMENTS are not fetched. wp:attachment_url points at a file on the SOURCE
  #    site; downloading it is an outbound HTTP request per record, and the screen's
  #    "Download and import file attachments" option is therefore shown disabled rather
  #    than shown working. Every attachment item is REPORTED as skipped, one line each.
  #  · The eleven machinery post types AD-02 split out of `posts` (nav_menu_item,
  #    wp_template, revision, …) are not content and are reported as skipped by type.
  #  · No plugin importers. AD-01: there is no extension system for one to register with,
  #    which is the whole reason this screen is an importer instead of a plugin list.
  class Run
    # AD-02: the CONTENT types. Everything else in a WXR's `wp:post_type` is machinery
    # or an attachment, and is reported rather than guessed at.
    CONTENT_TYPES = { "post" => "Publishing::Article", "page" => "Publishing::Page" }.freeze

    # AD-03: postmeta keys core itself owns are already columns, associations or tables,
    # so they are NOT copied into the residual bucket. Mirrors
    # Seeding::Pipeline::PROMOTED_POST_META — restated rather than referenced because
    # Seeding::Pipeline opens a connection to the oracle's MySQL at load, and a console
    # request must not drag that in.
    PROMOTED_POST_META = %w[
      _thumbnail_id _wp_page_template _wp_trash_meta_status _wp_trash_meta_time
      _wp_old_slug _wp_old_date _edit_lock _edit_last
      _wp_attached_file _wp_attachment_metadata _wp_attachment_image_alt
      _wp_desired_post_slug _pingme _encloseme _menu_item_orphaned
      _menu_item_type _menu_item_menu_item_parent _menu_item_object_id _menu_item_object
      _menu_item_target _menu_item_classes _menu_item_xfn _menu_item_url
      _wp_attachment_backup_sizes _wp_attachment_context
    ].freeze

    # The taxonomies the legacy registers hierarchical (register_taxonomy calls in
    # wp-includes/taxonomy.php). Same list the seeding pipeline uses.
    HIERARCHICAL_TAXONOMIES = %w[category nav_menu wp_template_part_area wp_pattern_category].freeze

    T = Seeding::Transformations

    attr_reader :result, :document

    # `author_mapping` is {wxr_login => {"mode" => "existing"|"create"|"skip",
    # "user_id" => id}}. The screen builds it; the default for an unnamed author is
    # `create`, which is what the WordPress importer's own "or create new user" arm does.
    def initialize(document, author_mapping: {}, fetch_attachments: false, actor: nil)
      @document = document
      @author_mapping = author_mapping || {}
      @fetch_attachments = fetch_attachments
      @actor = actor
      @result = Result.new
      @map = Hash.new { |h, k| h[k] = {} } # :users / :author_ids / :terms / :term_ids / :posts / :comments
      @pending_comments = []
    end

    def call
      ActiveRecord::Base.transaction do
        import_authors
        import_terms
        import_items
        import_comments
        recompute_counts
      end
      @result
    end

    # ── 1. Authors ───────────────────────────────────────────────────────────────
    #
    # export.php's own instructions for this step, verbatim (:507-509): "You will first
    # be asked to map the authors in this export file to users on the site. For each
    # author, you may choose to map to an existing user on the site or to create a new
    # user." Those are the only two arms, plus a third the screen offers explicitly —
    # skip, which leaves the imported records author-less rather than inventing an owner.
    def import_authors
      @document.author_keys.each do |key|
        author = @document.author_for(key)
        choice = @author_mapping[key] || @author_mapping[key.to_s] || {}
        mode = choice["mode"].presence || choice[:mode].presence || "create"
        target_id = choice["user_id"].presence || choice[:user_id].presence

        case mode
        when "skip"
          @result.record!(kind: "author", label: key, outcome: :skipped,
                          detail: "not assigned; imported records keep no author")
        when "existing"
          user = Identity::User.find_by(id: target_id)
          if user.nil?
            @result.record!(kind: "author", label: key, outcome: :failed,
                            detail: "the selected user no longer exists")
          else
            map_author(author, key, user)
            @result.record!(kind: "author", label: key, outcome: :existing,
                            detail: "mapped to #{user.login}")
          end
        else
          create_or_reuse_author(author, key)
        end
      end
    end

    def create_or_reuse_author(author, key)
      email = author&.email.to_s
      existing = Identity::User.find_by(login: key)
      existing ||= Identity::User.find_by(email: email) if email.present?
      if existing
        map_author(author, key, existing)
        @result.record!(kind: "author", label: key, outcome: :existing,
                        detail: "an account with this login already exists")
        return
      end

      # T-10 in reverse: a WXR carries NO password, by design (export.php never writes
      # one). The account is therefore created with authentication DISABLED rather than
      # with a guessable or blank credential — the same refusal Seeding::Transformations
      # makes for a corpus user whose digest is unusable. The operator resets it from
      # console.users, which is the only honest way in.
      user = Identity::User.new(
        login: key,
        email: email.presence || placeholder_email(key),
        nicename: allocate_nicename(key),
        display_name: author&.display_name.presence || key,
        password_digest: T::DISABLED_DIGEST,
        registered_at: Time.current
      )
      if user.save
        # wp_insert_user() :2658-2662: no explicit role -> `get_option( 'default_role' )`.
        # ⚠️ `Setting[]` answers `false` for a name that is not stored, and "false".presence
        # is truthy — so the guard is on the TYPE, not on presence. Registration reaches the
        # same default for the signup form.
        stored = Configuration::Setting["default_role"]
        user.assign_role(stored.is_a?(String) && stored.present? ? stored : "subscriber")
        map_author(author, key, user)
        @result.record!(kind: "author", label: key, outcome: :imported,
                        detail: "created with authentication disabled (the export carries no password)")
      else
        @result.record!(kind: "author", label: key, outcome: :failed,
                        detail: user.errors.full_messages.join("; "))
      end
    end

    def map_author(author, key, user)
      @map[:users][key] = user.id            # dc:creator -> user
      @map[:author_ids][author.id] = user.id if author&.id # wp:comment_user_id -> user
    end

    # wp_insert_user() :2355: "build a nicename from the user_login" — sanitize_title()
    # over the first 50 characters, with a numeric suffix when it is already held. The
    # column is UNIQUE here (the legacy had a non-unique KEY), so the suffix is not
    # optional; Identity::Registration does the same walk for the signup form.
    def allocate_nicename(login)
      base = Sanitizing::Formatting.sanitize_title(login.to_s[0, 50]).to_s
      base = "imported" if base.empty?
      return base unless Identity::User.exists?(nicename: base)

      suffix = 2
      suffix += 1 while Identity::User.exists?(nicename: "#{base[0, 49 - suffix.to_s.length]}-#{suffix}")
      "#{base[0, 49 - suffix.to_s.length]}-#{suffix}"
    end

    def placeholder_email(key)
      # An export with no author block still names creators. A unique, obviously-fake
      # address beats refusing the import or silently reusing somebody else's.
      "#{key.parameterize.presence || 'imported'}@imported.invalid"
    end

    # ── 2. Terms ─────────────────────────────────────────────────────────────────
    #
    # wp:category / wp:tag / wp:term. Two passes for `wp:term_parent`, which names the
    # PARENT'S SLUG (export.php:568) rather than an id — so the map is keyed by
    # (taxonomy, slug), not by the source term_id.
    def import_terms
      pending = @document.terms.reject { |t| t.slug.to_s.strip.empty? }
      2.times { pending = pending.reject { |t| insert_term(t) } }
      pending.each { |t| insert_term(t, force_root: true) }
    end

    def insert_term(source, force_root: false)
      taxonomy_name = source.taxonomy.to_s.presence || "category"
      parent_slug = source.parent_slug.to_s
      parent = parent_slug.empty? ? nil : @map[:terms][[taxonomy_name, parent_slug]]
      return false if !parent_slug.empty? && parent.nil? && !force_root

      taxonomy = taxonomy_for(taxonomy_name)
      existing = Classification::Term.find_by(taxonomy_id: taxonomy.id, slug: source.slug)
      if existing
        @map[:terms][[taxonomy_name, source.slug]] = existing.id
        @map[:term_ids][source.id] = existing.id if source.id
        @result.record!(kind: "term", label: "#{taxonomy_name}/#{source.slug}", outcome: :existing)
        return true
      end

      term = Classification::Term.new(taxonomy: taxonomy, parent_id: parent,
                                      name: source.name.presence || source.slug,
                                      slug: source.slug, description: T.text(source.description))
      if term.save
        @map[:terms][[taxonomy_name, source.slug]] = term.id
        @map[:term_ids][source.id] = term.id if source.id
        @result.record!(kind: "term", label: "#{taxonomy_name}/#{source.slug}", outcome: :imported)
      else
        @result.record!(kind: "term", label: "#{taxonomy_name}/#{source.slug}", outcome: :failed,
                        detail: term.errors.full_messages.join("; "))
      end
      true
    end

    def taxonomy_for(name)
      @taxonomies ||= {}
      @taxonomies[name] ||= Classification::Taxonomy.find_or_create_by!(name: name) do |t|
        t.hierarchical = HIERARCHICAL_TAXONOMIES.include?(name)
        t.object_types = %w[Publishing::Post]
      end
    end

    # ── 3. Items ─────────────────────────────────────────────────────────────────
    def import_items
      content, other = @document.items.partition { |i| CONTENT_TYPES.key?(item_type(i)) }
      other.each { |i| report_unsupported(i) }

      pending = content.dup
      2.times { pending = pending.reject { |i| insert_item(i) } }
      pending.each { |i| insert_item(i, force_root: true) }
    end

    # A WXR from a site whose export omitted wp:post_type (the field is optional in
    # WXR 1.0) is a `post`, which is what wp_insert_post() defaults to.
    def item_type(item) = item.post_type.to_s.presence || "post"

    def report_unsupported(item)
      type = item_type(item)
      if type == "attachment"
        detail = if @fetch_attachments
                   "attachment fetching is not available: the file lives on the source site " \
                   "(#{item.attachment_url.presence || 'no URL in the export'}) and this importer " \
                   "makes no outbound requests"
                 else
                   "attachments are not imported (#{item.attachment_url.presence || 'no URL in the export'})"
                 end
        @result.record!(kind: "attachment", label: item.label, outcome: :skipped, detail: detail)
      else
        @result.record!(kind: "other", label: "#{type}: #{item.label}", outcome: :skipped,
                        detail: "AD-02: `#{type}` is not a content type in this system")
      end
    end

    def insert_item(item, force_root: false)
      parent_source = item.post_parent.to_i
      parent_id = parent_source.zero? ? nil : @map[:posts][parent_source]
      return false if parent_source.positive? && parent_id.nil? && !force_root

      type = item_type(item)
      kind = type == "page" ? "page" : "post"

      begin
        status = T.post_status(item.status.to_s.presence || "draft")
      rescue ArgumentError => e
        @result.record!(kind: kind, label: item.label, outcome: :failed, detail: e.message)
        return true
      end

      published_at = published_at_for(item)
      if published_at.nil? && %w[published scheduled].include?(status)
        # posts_published_at_present, a CHECK constraint: the row is unrepresentable.
        # Reported rather than back-dated to `now`, which would invent a publication date.
        @result.record!(kind: kind, label: item.label, outcome: :failed,
                        detail: "status is `#{item.status}` but the export carries no publication date")
        return true
      end

      if (duplicate = existing_post(item, type, published_at))
        @map[:posts][item.post_id] = duplicate.id if item.post_id
        @result.record!(kind: kind, label: item.label, outcome: :existing,
                        detail: "a #{kind} with this slug is already here")
        assign_terms(duplicate, item)
        return true
      end

      post = CONTENT_TYPES.fetch(type).constantize.new(
        author_id: @map[:users][item.creator.to_s],
        parent_id: parent_id,
        title: T.text(item.title), content: T.text(item.content), excerpt: T.text(item.excerpt),
        status: status, published_at: published_at,
        modified_at: safe_time(item.post_modified_gmt) || published_at || Time.current,
        comment_status: item.comment_status.to_s.presence || "open",
        password_digest: T.post_password_digest(item.post_password),
        menu_order: item.menu_order.to_i,
        guid: T.fresh_guid, # T-07: the export's guid is a permalink on the SOURCE site.
        # AD-03 promoted comment_status and dropped ping_status; the value is still
        # observable output (Presentation::Head#comments_feed?), so it is parked rather
        # than lost — the same choice load_posts makes.
        residual_attributes: { "ping_status" => item.ping_status.to_s }
      )
      # BR-MIGRATE-032: a record leaving the slugless statuses needs a slug that is
      # unique in its (type, parent) scope AND clear of the reserved segments. The
      # allocator is asked for one seeded with the export's own post_name, so an
      # unchanged slug survives the round trip and a colliding one gets a suffix instead
      # of raising on the partial unique index (AD-05).
      post.slug = allocate_slug(post, item) if post.slug_required?

      unless post.save
        @result.record!(kind: kind, label: item.label, outcome: :failed,
                        detail: post.errors.full_messages.join("; "))
        return true
      end

      @map[:posts][item.post_id] = post.id if item.post_id
      @result.record!(kind: kind, label: item.label, outcome: :imported)
      assign_terms(post, item)
      import_post_meta(post, item)
      item.comments.each { |c| @pending_comments << [post, c] }
      true
    end

    def allocate_slug(post, item)
      Routing::SlugAllocator.new.allocate(post, requested: item.post_name.presence)
    rescue StandardError
      nil
    end

    # AD-07: post_date_gmt is the truth. pubDate (RFC 822, always +0000 in a WXR,
    # export.php:637) is the fallback for an export that omitted it — the rebuild's own
    # Platform::Export historically wrote only pubDate and wp:post_date.
    def published_at_for(item)
      safe_time(item.post_date_gmt) ||
        (item.pub_date.present? ? (Time.zone.parse(item.pub_date) rescue nil) : nil) ||
        safe_time(item.post_date)
    end

    def safe_time(raw)
      T.zero_date_to_null(raw)
    rescue ArgumentError
      nil
    end

    # `post_exists()` (wp-admin/includes/post.php): an item already present is REPORTED,
    # not duplicated, so re-running an import is idempotent instead of doubling the site.
    #
    # ⚠️ Matched on TITLE + publication instant within the type, which is post_exists()'s
    # own key — deliberately NOT on the slug. A slug is unique by construction (AD-05), so
    # matching on it would declare any UNRELATED record that happens to occupy the same
    # slug to be "already imported" and silently drop the incoming one. A colliding slug is
    # a naming conflict for the allocator to resolve, not evidence of a duplicate. An item
    # with no title falls back to the slug, because then there is nothing else to match on.
    def existing_post(item, type, published_at)
      klass = CONTENT_TYPES.fetch(type).constantize
      return klass.find_by(slug: item.post_name) if item.title.to_s.strip.empty? && item.post_name.present?

      klass.find_by(title: item.title, published_at: published_at)
    end

    # <category domain="…" nicename="…"> — a REFERENCE. A term the channel never defined
    # is created here, which is what makes an export that carries only item-level
    # categories still import its taxonomy.
    def assign_terms(post, item)
      ids = item.terms.filter_map do |ref|
        next if ref.nicename.to_s.strip.empty?

        taxonomy_name = ref.domain.to_s.presence || "category"
        @map[:terms][[taxonomy_name, ref.nicename]] || begin
          taxonomy = taxonomy_for(taxonomy_name)
          term = Classification::Term.find_by(taxonomy_id: taxonomy.id, slug: ref.nicename)
          term ||= Classification::Term.create(taxonomy: taxonomy, slug: ref.nicename,
                                               name: ref.name.presence || ref.nicename)
          next unless term&.persisted?

          @map[:terms][[taxonomy_name, ref.nicename]] = term.id
        end
      end
      return if ids.empty?

      # BR-MIGRATE-058: `append: true` — an import ADDS terms, it does not strip terms an
      # existing record already carries.
      Classification::Assignment.set(post, ids, append: true)
    end

    # AD-03 + AD-05, the same split load_post_attributes makes: a key with ONE value is a
    # row (and the unique index is the guarantee); a key with SEVERAL cannot satisfy that
    # index and lands in the jsonb bucket as an array, preserving BR-MIGRATE-028's
    # insertion order.
    def import_post_meta(post, item)
      grouped = item.meta.each_with_object({}) do |(key, value), acc|
        next if key.to_s.empty? || PROMOTED_POST_META.include?(key)

        (acc[key] ||= []) << decode(key, value, item)
      end
      return if grouped.empty?

      residual = {}
      grouped.each do |key, values|
        if values.length == 1
          row = Publishing::Attribute.new(post: post, key: key, value: values.first.to_json)
          @result.note!("#{item.label}: custom field #{key.inspect} not imported — #{row.errors.full_messages.join("; ")}") unless row.save
        else
          residual[key] = values
        end
      end
      post.update_column(:residual_attributes, post.residual_attributes.merge(residual)) if residual.any?
    end

    # T-02: a WXR carries meta values exactly as they sit in wp_postmeta, which means
    # PHP serialize() payloads travel verbatim. They are decoded here through the SAME
    # parser the seeding pipeline uses, so the two loaders cannot disagree about what
    # `a:0:{}` means. An O: payload has no automatic mapping and is NEVER guessed at
    # (RISK-006): the raw bytes are kept and the run says so.
    def decode(key, raw, item)
      _kind, value = Seeding::PhpSerialization.parse(raw)
      value
    rescue Seeding::PhpSerialization::UnmappableObject, Seeding::PhpSerialization::ParseError => e
      @result.note!("#{item.label}: custom field #{key.inspect} kept as raw bytes — #{e.message}")
      raw
    end

    # ── 4. Comments ──────────────────────────────────────────────────────────────
    #
    # Collected across EVERY item first, then walked in two passes: wp:comment_parent
    # points at a source comment id that may belong to an item later in the document.
    def import_comments
      pending = @pending_comments.dup
      2.times { pending = pending.reject { |(post, c)| insert_comment(post, c) } }
      pending.each { |(post, c)| insert_comment(post, c, force_root: true) }
    end

    def insert_comment(post, source, force_root: false)
      parent_source = source.parent_id.to_i
      parent_id = parent_source.zero? ? nil : @map[:comments][parent_source]
      return false if parent_source.positive? && parent_id.nil? && !force_root

      label = "#{post.title.presence || post.slug}: #{source.author_name.presence || 'anonymous'}"

      begin
        # T-05. export.php never writes `spam` (:686 excludes it), so an unmapped value
        # here is a genuinely foreign file and is reported rather than defaulted.
        status = T.comment_status(source.approved.to_s.presence || "1")
      rescue ArgumentError => e
        @result.record!(kind: "comment", label: label, outcome: :failed, detail: e.message)
        return true
      end

      submitted = safe_time(source.date_gmt) || safe_time(source.date) || Time.current

      if Discussion::Comment.exists?(post_id: post.id, author_name: T.text(source.author_name),
                                     submitted_at: submitted)
        @result.record!(kind: "comment", label: label, outcome: :existing)
        return true
      end

      comment = Discussion::Comment.new(
        post: post, parent_id: parent_id,
        user_id: @map[:author_ids][source.user_id],
        author_name: T.text(source.author_name),
        author_email: source.author_email.presence,
        author_url: source.author_url.presence,
        author_ip: valid_ip(source.author_ip),
        content: T.text(source.content),
        status: status, kind: source.kind.presence || "comment",
        submitted_at: submitted
      )
      # The same ruling load_comments makes: an imported thread's DEPTH is a fact about
      # the file, not a request to re-evaluate `thread_comments_depth` against a setting
      # this site happens to hold. The depth rule governs new submissions.
      comment.define_singleton_method(:thread_depth_within_limit) { nil }

      if comment.save
        @map[:comments][source.id] = comment.id if source.id
        @result.record!(kind: "comment", label: label, outcome: :imported)
      else
        @result.record!(kind: "comment", label: label, outcome: :failed,
                        detail: comment.errors.full_messages.join("; "))
      end
      true
    end

    # `comments.author_ip` is `inet`; the legacy's varchar accepted anything, including
    # the empty string every CLI-created comment carries.
    def valid_ip(raw)
      value = raw.to_s.strip
      return nil if value.empty?

      IPAddr.new(value)
      value
    rescue StandardError
      nil
    end

    # BR-MIGRATE-061/062: `terms.count` is a stored counter maintained by a database
    # trigger (db/migrate/…_maintain_term_counts.rb), so it is already correct here. The
    # reconciliation command is run anyway on exactly the terms this import touched —
    # cheap, and it is the one place an import could otherwise leave a visible drift.
    def recompute_counts
      Classification::Term.where(id: @map[:terms].values.uniq).find_each(&:recompute_count!)
    end
  end
end
