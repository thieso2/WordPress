# frozen_string_literal: true

module Access
  # The successor to map_meta_cap()'s 870-line switch (F-CAP-01) -- the `edit_post`,
  # `delete_post`, `read_post` and `publish_post` arms, wp-includes/capabilities.php
  # :81-423, ported line for line and verified against the live oracle for every corpus
  # role x every corpus post (spec/models/access/capability_matrix_differential_spec.rb).
  #
  # This class is why the users<->posts cycle is gone: it reads BOTH Identity::User and
  # Publishing::Post, and neither of them reads it.
  #
  # ⚠️ AD-01: the legacy closes every arm with `apply_filters('map_meta_cap', ...)`. There
  # is no filter here. The list each method returns IS the requirement, permanently.
  class PostPolicy < BasePolicy
    # Legacy post_status values that count as "published or scheduled" in every arm:
    # `in_array( $post->post_status, array( 'publish', 'future' ), true )`.
    PUBLISHED_LIKE = %w[published scheduled].freeze

    # Chooses the policy for a Publishing::Post subtype, so a caller holding "some post"
    # (a comment's post, a revision's parent) gets the page capability family when the
    # record is a page. `get_post_type_object( $post->post_type )->cap`.
    def self.for(actor, record)
      (record.is_a?(Publishing::Page) ? PagePolicy : PostPolicy).new(actor, record)
    end

    def required_capabilities(action)
      case action.to_sym
      when :read    then read_post
      when :edit    then edit_post
      when :delete  then delete_post
      when :publish then publish_post
      else
        # BR-CAP-05, reproduced: an UNKNOWN action yields no capabilities, and no
        # capabilities ALLOWS. The legacy behaves identically -- map_meta_cap() returns
        # an empty array for a capability it does not recognise. This is the single most
        # surprising line in the authorization model and it is deliberate.
        []
      end
    end

    private

    # The capability family. `$post_type->cap->edit_posts` etc. -- PagePolicy swaps the
    # `_posts` suffix for `_pages`; `read` and `manage_options` have no family form.
    def cap(name) = name.to_s

    # `$post->post_author && $user_id === (int) $post->post_author`. A post with no
    # author is nobody's, so it always takes the `_others_` branch.
    def owner?
      record.author_id.present? && record.author_id == actor_id && actor_id.positive?
    end

    def published_like?(status) = PUBLISHED_LIKE.include?(status.to_s)

    # ── edit_post / edit_page, capabilities.php:188-285 ───────────────────────────
    #
    # "edit_post breaks down to edit_posts, edit_published_posts, or edit_others_posts."
    def edit_post
      return [DO_NOT_ALLOW] if record.nil?                       # :78 / :209 (BR-MIGRATE-106)

      caps = ownership_scoped("edit")
      caps += privacy_policy_guard
      caps
    end

    # ── delete_post / delete_page, capabilities.php:81-186 ────────────────────────
    def delete_post
      return [DO_NOT_ALLOW] if record.nil?                       # :78 (BR-MIGRATE-106)

      # :112-116: the posts page and the static front page are site settings, so
      # deleting either requires `manage_options` -- and NOTHING else: the arm breaks
      # before the ownership branch and before the privacy-policy guard.
      if record.id == setting_id("page_for_posts") || record.id == setting_id("page_on_front")
        return ["manage_options"]
      end

      caps = ownership_scoped("delete")
      caps += privacy_policy_guard
      caps
    end

    # ── read_post / read_page, capabilities.php:287-380 ───────────────────────────
    def read_post
      return [DO_NOT_ALLOW] if record.nil?

      # `$status_obj->public`: of the seven statuses only `publish` is public
      # (post.php, register_post_status). `$post_type->cap->read` is `read` for both
      # posts and pages.
      return ["read"] if record.published?

      if owner?
        ["read"]
      elsif record.private?
        [cap("read_private_posts")]
      else
        # :378: `$caps = map_meta_cap( 'edit_post', $user_id, $post->ID )`
        edit_post
      end
    end

    # ── publish_post, capabilities.php:382-422 ────────────────────────────────────
    def publish_post
      return [DO_NOT_ALLOW] if record.nil?

      [cap("publish_posts")]
    end

    # map_meta_cap's central distinction: whether the actor owns the record decides
    # between the plain and the `_others_` capability -- and the status adds the
    # `_published_` / `_private_` requirement. :150-175 (delete) and :257-282 (edit);
    # the two arms are textually identical apart from the verb.
    def ownership_scoped(verb)
      if owner?
        # :152-163. A trashed post is judged by the status it held BEFORE the trash:
        # `_wp_trash_meta_status` in the legacy, `status_before_trash` here (AD-03).
        status = record.trashed? ? record.status_before_trash : record.status
        published_like?(status) ? [cap("#{verb}_published_posts")] : [cap("#{verb}_posts")]
      else
        # :166-173. "The user is trying to edit someone else's post." The extra cap is
        # required for published/scheduled and for private; NOT for trash, where the
        # legacy does not consult the pre-trash status for non-owners.
        caps = [cap("#{verb}_others_posts")]
        if published_like?(record.status)
          caps << cap("#{verb}_published_posts")
        elsif record.private?
          caps << cap("#{verb}_private_posts")
        end
        caps
      end
    end

    # :178-184 / :284-290. "Setting the privacy policy page requires
    # `manage_privacy_options`, so editing it should require that too." That arm (:797)
    # maps to `manage_options` on a single site.
    def privacy_policy_guard
      record.id == setting_id("wp_page_for_privacy_policy") ? ["manage_options"] : []
    end
  end
end
