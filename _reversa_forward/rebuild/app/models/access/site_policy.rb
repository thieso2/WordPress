# frozen_string_literal: true

module Access
  # The record-less arms of map_meta_cap() and its `default:` arm (capabilities.php
  # :587-706, :751-760, :795-798, :846-865): `user_can( $user_id, $capability )` with
  # no object. The action IS the capability name.
  #
  #   Access::SitePolicy.new(actor, nil).permit?(:upload_files)
  #   Access::SitePolicy.new(actor, nil).permit?(:manage_categories)
  #
  # The `default:` arm is the whole reason a primitive can be asked for directly: "If no
  # meta caps match, return the original cap." (:864). So `edit_posts` requires
  # `edit_posts`, and an unknown capability requires itself -- which nobody holds, so
  # `user_can(1, 'nonsense_cap')` is false on the oracle and false here. That is the
  # one place the switch is NOT permissive: an unknown CAPABILITY denies, while an
  # unknown ACTION on an object policy allows (BR-CAP-05). Both are the legacy's.
  class SitePolicy < BasePolicy
    # :846-857: "Block capabilities map to their post equivalent."
    BLOCK_CAPABILITIES = %w[
      edit_blocks edit_others_blocks publish_blocks read_private_blocks delete_blocks
      delete_private_blocks delete_published_blocks delete_others_blocks
      edit_private_blocks edit_published_blocks
    ].freeze

    def required_capabilities(capability)
      name = capability.to_s
      case name
      # :587-592. ALLOW_UNFILTERED_UPLOADS is not defined, so the arm denies for
      # everyone, administrators included -- the role holds the capability and can
      # never exercise it. AD-01 / no wp-config constant to set: permanent.
      when "unfiltered_upload" then [DO_NOT_ALLOW]
      # :594-604. DISALLOW_UNFILTERED_HTML is not defined and this is a single site,
      # so both map to the `unfiltered_html` primitive (editor and administrator).
      when "edit_css", "unfiltered_html" then ["unfiltered_html"]
      # :61-80 on the plural: `edit_users` without an object.
      when "edit_users" then actor_id < 1 ? [DO_NOT_ALLOW] : ["edit_users"]
      when "delete_user", "delete_users" then ["delete_users"]        # :673-680
      when "create_users" then ["create_users"]                       # :682-690
      when "promote_user", "add_users" then ["promote_users"]         # :57-59
      when "remove_user", "remove_users" then ["remove_users"]        # :49-56, no object
      # :691-697. `link_manager_enabled` is 0 on every install since 3.5 and in the
      # corpus, so this denies even the editor and administrator who hold it.
      when "manage_links" then setting_truthy?("link_manager_enabled") ? [name] : [DO_NOT_ALLOW]
      when "customize" then ["edit_theme_options"]                    # :698-700
      when "delete_site" then [DO_NOT_ALLOW]                          # :701-707, single site
      when "export_others_personal_data", "erase_others_personal_data",
           "manage_privacy_options" then ["manage_options"]           # :795-798, single site
      when "manage_post_tags", "edit_categories", "edit_post_tags",
           "delete_categories", "delete_post_tags" then ["manage_categories"] # :751-757
      when "assign_categories", "assign_post_tags" then ["edit_posts"]        # :758-760
      when *BLOCK_CAPABILITIES then [name.sub("_blocks", "_posts")]
      # Object-requiring arms asked for without an object: BR-MIGRATE-106 (BR-CAP-10),
      # "fail closed" -- :78, :209, :298, :384, :567, :711.
      when "edit_post", "edit_page", "delete_post", "delete_page", "read_post", "read_page",
           "publish_post", "edit_comment", "edit_term", "delete_term", "assign_term"
        [DO_NOT_ALLOW]
      else [name]                                                      # :864, the default arm
      end
    end

    private

    def setting_truthy?(name)
      value = Configuration::Setting[name]
      value.present? && value.to_s != "0"
    end
  end
end
