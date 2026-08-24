# frozen_string_literal: true

module Access
  # The capability sets behind the five built-in roles.
  #
  # Legacy origin: populate_roles() in wp-admin/includes/schema.php, which writes a
  # serialized role => capability map into the options table at install time. Here the
  # catalogue is code, because it is a fact about the product rather than site data --
  # and because a serialized blob in a settings row is exactly what AD-06 removed.
  #
  # Verified against the oracle's own `get_role($name)->capabilities` for all five
  # roles (spec/models/access/role_catalogue_differential_spec.rb), which is how the
  # five administrator capabilities an earlier transcription had dropped
  # (edit_theme_options, install_plugins, update_plugins, delete_plugins,
  # unfiltered_upload) were found.
  #
  # BR-CAP-11's level_0..level_10 capabilities are NOT reproduced: they exist in every
  # legacy role only for backward compatibility with plugins that still test for them
  # (TD-17, ADR-002), a compatibility burden migration_brief.md has deleted.
  module RoleCatalogue
    SUBSCRIBER = %w[read].freeze

    CONTRIBUTOR = (SUBSCRIBER + %w[
      edit_posts delete_posts
    ]).freeze

    # BR-MIGRATE-110 (BR-CAP-15): contributors can neither publish posts nor upload
    # files -- both capabilities first appear here.
    AUTHOR = (CONTRIBUTOR + %w[
      publish_posts upload_files edit_published_posts delete_published_posts
    ]).freeze

    EDITOR = (AUTHOR + %w[
      edit_others_posts delete_others_posts read_private_posts edit_private_posts
      delete_private_posts publish_pages edit_pages edit_others_pages edit_published_pages
      delete_pages delete_others_pages delete_published_pages read_private_pages
      edit_private_pages delete_private_pages manage_categories manage_links
      moderate_comments unfiltered_html
    ]).freeze

    ADMINISTRATOR = (EDITOR + %w[
      switch_themes edit_themes activate_plugins edit_plugins edit_users edit_files
      manage_options import export list_users remove_users promote_users
      delete_themes delete_users create_users update_core update_themes install_themes
      edit_dashboard edit_theme_options install_plugins update_plugins delete_plugins
      unfiltered_upload
    ]).freeze

    ROLES = {
      "subscriber" => SUBSCRIBER, "contributor" => CONTRIBUTOR, "author" => AUTHOR,
      "editor" => EDITOR, "administrator" => ADMINISTRATOR
    }.freeze

    module_function

    # ⚠️ An UNKNOWN role contributes nothing rather than raising. T-03 requires unknown
    # roles to load ("An unknown role is data, not corruption"), so they must also be
    # evaluable. Contributing nothing is the conservative reading, and it is the only
    # place in this file that is stricter than the legacy.
    def capabilities_for(roles)
      Array(roles).flat_map { |role| ROLES.fetch(role.to_s, []) }.uniq
    end

    def known?(role) = ROLES.key?(role.to_s)
  end
end
