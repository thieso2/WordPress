# frozen_string_literal: true

module Access
  # AD-02 split attachments out of wp_posts, but the legacy authorizes them as posts:
  # the `attachment` post type is registered with `capability_type => 'post'` and
  # `map_meta_cap => true` (wp-includes/post.php, create_initial_post_types), so
  # `edit_post` / `delete_post` on an attachment run the post arms (capabilities.php
  # :81-285) against post_status 'inherit' -- which is neither published nor private,
  # so the owner needs the plain capability and anyone else the `_others_` one.
  #
  # `upload_files` is a primitive and maps to itself (the `default:` arm, :860).
  #
  # ⚠️ The privacy-policy / front-page guards are NOT applied here. In the legacy they
  # compare `$post->ID` against a page id, and attachments shared that id space; assets
  # have their own sequence here, so the comparison would match a different object.
  class AssetPolicy < BasePolicy
    def required_capabilities(action)
      case action.to_sym
      when :upload then ["upload_files"]
      when :edit   then attachment_scoped("edit")
      when :delete then attachment_scoped("delete")
      else []
      end
    end

    private

    def attachment_scoped(verb)
      return [DO_NOT_ALLOW] if record.nil?

      owner? ? ["#{verb}_posts"] : ["#{verb}_others_posts"]
    end

    def owner?
      record.uploader_id.present? && record.uploader_id == actor_id && actor_id.positive?
    end
  end
end
