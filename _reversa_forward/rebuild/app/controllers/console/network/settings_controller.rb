# frozen_string_literal: true

module Console
  module Network
    # console.ms-options — ms-options.php → wp-admin/network/settings.php, "Network Settings".
    # The network-wide half of the options split (BR-MS-08 / BR-MIGRATE-363): every field
    # here is a `Tenancy::NetworkSetting` row, the wp_sitemeta replacement. The per-site half
    # (wp_blogmeta) is just Configuration::Setting inside each tenant schema and is edited on
    # the Edit Site → Settings tab.
    #
    # The sections and their order are wp-admin's own (settings.php:156-450):
    #   Operational Settings · Registration Settings · New Site Settings · Upload Settings
    #
    # ⚠️ Two of the legacy's sections are ABSENT and their absence is a ruling, not a gap:
    #   * Menu Settings (settings.php:503-520) exists solely to show/hide the PLUGINS menu
    #     for site admins. AD-01 removed the extension system; there is no plugins menu to
    #     govern, so the setting would govern nothing.
    #   * Language Settings (:457-470) sets the network's default WPLANG. Localization owns
    #     the locale cascade in this rebuild and the network default has no consumer yet;
    #     recorded as deferred rather than shipped inert.
    #
    # Every label, radio and description below is VERBATIM from network/settings.php.
    class SettingsController < BaseController
      self.network_capability = "manage_network_options"

      # settings.php:142 — add_settings_error( ..., __( 'Settings saved.' ) ).
      SAVED_NOTICE = "Settings saved."

      # name => default. The defaults are the legacy's own get_site_option() fallbacks.
      TEXT_FIELDS = {
        "site_name" => "", "admin_email" => "", "illegal_names" => "",
        "limited_email_domains" => "", "banned_email_domains" => "",
        "welcome_email" => "", "welcome_user_email" => "",
        "first_post" => "", "first_page" => "", "first_comment" => "",
        "first_comment_author" => "", "first_comment_email" => "", "first_comment_url" => "",
        "upload_filetypes" => "jpg jpeg png gif"
      }.freeze

      NUMERIC_FIELDS = { "blog_upload_space" => 100, "fileupload_maxk" => 300 }.freeze

      BOOLEAN_FIELDS = %w[registrationnotification add_new_users].freeze

      # settings.php:214-217 — the four registration modes, in the legacy's order.
      REGISTRATION_MODES = %w[none user blog all].freeze

      # GET /console/network/settings
      def show
        prepare
        render "console/network/settings/show"
      end

      # POST /console/network/settings — settings.php:70-140 (`action=siteoptions`).
      def update
        without_tenant do
          TEXT_FIELDS.each_key do |name|
            next unless params.key?(name)

            Tenancy::NetworkSetting[name] = params[name].to_s
          end
          NUMERIC_FIELDS.each_key do |name|
            next unless params.key?(name)

            Tenancy::NetworkSetting[name] = params[name].to_s.to_i
          end
          BOOLEAN_FIELDS.each do |name|
            Tenancy::NetworkSetting[name] = params[name].present?
          end
          # :404 — the legacy renders this box INVERTED: `checked( (bool)
          # get_site_option( 'upload_space_check_disabled' ), false )`. The label reads
          # "Limit total size of files uploaded to", so a TICKED box means the check is on,
          # i.e. `upload_space_check_disabled` is FALSE. Reproduced rather than tidied.
          Tenancy::NetworkSetting["upload_space_check_disabled"] = params["upload_space_check_disabled"].blank?
          # :202-217 — `registration` is a radio, so an unknown value is simply not stored.
          registration = params[:registration].to_s
          Tenancy::NetworkSetting["registration"] = registration if REGISTRATION_MODES.include?(registration)
        end
        redirect_after_submit("/console/network/settings", notice: SAVED_NOTICE)
      end

      private

      def prepare
        @page_title = "Network Settings"
        @screen = "console.ms-options"
        @network_nav_key = "console.ms-options"

        without_tenant do
          @values = TEXT_FIELDS.to_h { |name, default| [name, (Tenancy::NetworkSetting[name] || default).to_s] }
          NUMERIC_FIELDS.each { |name, default| @values[name] = (Tenancy::NetworkSetting[name] || default).to_i }
          BOOLEAN_FIELDS.each { |name| @values[name] = Tenancy::NetworkSetting[name] == true }
          @values["upload_space_check_disabled"] = Tenancy::NetworkSetting["upload_space_check_disabled"] == true
          # :204 — the legacy's default is 'none' (registration closed).
          @registration = (Tenancy::NetworkSetting["registration"] || "none").to_s
        end
      end
    end
  end
end
