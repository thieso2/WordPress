# frozen_string_literal: true

module Console
  # The nine settings screens (target_screens.md § Settings screens, modernized mode).
  # options-*.php reduced to a family driven by Configuration::SettingsRegistry: each
  # section DECLARES its fields (DEV-002), the titles and labels are LITERAL, and a save
  # casts the form's string params to each option's shape and writes them through
  # `Configuration::Setting.set`.
  #
  # `console.options` — the legacy's generic options.php POST target — is deliberately
  # NOT reproduced (DEV-002): there is no whitelist-driven blind writer here, only the
  # typed sections below.
  #
  # ── Authorization ────────────────────────────────────────────────────────────────
  # Declared `:authenticated` (config/initializers/authorization_declarations.rb), then
  # gated in-controller on the site capability. Two reasons it is not declared `:policy`:
  # the wp_die() refusal string is a LITERAL the modernized contract must render
  # verbatim (a `:policy` denial is a bare 403), and `options-privacy` opens on a
  # DIFFERENT capability (`manage_privacy_options`) than the other eight
  # (`manage_options`). The capability is still enforced — `require_capability!` — just
  # inside the surface where the right message is reachable.
  class SettingsController < BaseController
    include Chrome

    # options-general.php:15 etc. Every screen but privacy.
    MANAGE_OPTIONS_DENIED = "Sorry, you are not allowed to manage options for this site."
    # options-privacy.php:13.
    MANAGE_PRIVACY_DENIED = "Sorry, you are not allowed to manage privacy options on this site."

    # The sections this controller renders and saves generically. permalinks and privacy
    # have their own write paths (see #update).
    PLAIN_SECTIONS = %w[general writing reading discussion media].freeze
    SECTIONS = (PLAIN_SECTIONS + %w[permalinks privacy connectors]).freeze

    # get_submit_button() default (wp-admin/includes/template.php:2600).
    SAVE_BUTTON = "Save Changes"
    # options.php's success notice (options.php add_settings_error 'settings_updated').
    SAVED_NOTICE = "Settings saved."

    before_action :resolve_section
    before_action :guard_capability

    def show
      render "console/settings/#{@section}"
    end

    def update
      case @section
      when "permalinks" then update_permalinks
      when "privacy"    then update_privacy
      when "connectors" then update_connectors
      else                   update_plain
      end
    end

    private

    def resolve_section
      @section = (params[:section].presence || "general").to_s
      raise ActionController::RoutingError, "unknown settings section" unless SECTIONS.include?(@section)
    end

    # options-privacy.php gates on manage_privacy_options; the other eight on
    # manage_options. Both map through Access::SitePolicy (manage_privacy_options ->
    # manage_options on a single site, capabilities.php:795).
    def guard_capability
      if @section == "privacy"
        require_capability!("manage_privacy_options", MANAGE_PRIVACY_DENIED)
      else
        require_capability!("manage_options", MANAGE_OPTIONS_DENIED)
      end
    end

    # A plain section: cast every declared field and write it. RISK-008: params are
    # already unslashed by Rails; nothing here adds or strips a slash.
    def update_plain
      Configuration::SettingsRegistry.section(@section).each do |field|
        raw = params[field.name]
        # An absent checkbox submits nothing; cast(nil) yields the "off" value, which is
        # the legacy's behaviour for a settings form (a cleared checkbox is stored '0').
        Configuration::Setting.set(field.name, field.cast(raw))
      end
      redirect_after_submit(settings_path_for(@section), notice: SAVED_NOTICE)
    end

    # ⚠️ options-permalink.php, the one screen where a setting changes which slugs are
    # legal (BR-POST-07, F-RW-06). The write goes through the aggregate that recomputes
    # the reserved-segment set and REFUSES a structure that would shadow an already
    # published slug — a conflict the legacy resolves silently by leaving the post
    # unreachable. On refusal the form re-renders with the collisions named.
    def update_permalinks
      # options-permalink.php:118-140: `$_POST['selection']` names the chosen preset (its
      # value IS the structure, "" for Plain); the literal "custom" defers to the text
      # field. One radio is always checked, so `selection` is always present.
      pattern = if params[:selection].to_s == "custom"
                  params[:permalink_structure].to_s
                else
                  params[:selection].to_s
                end
      @change = Routing::PermalinkStructure.change_to(pattern)

      if @change.applied?
        redirect_after_submit(settings_path_for("permalinks"), notice: "Permalink structure updated.")
      else
        @permalink_conflicts = @change.conflicts
        flash.now[:notice] = nil
        render "console/settings/permalinks", status: :unprocessable_content
      end
    end

    # options-privacy.php: choose (or clear) the page whose id is stored in
    # wp_page_for_privacy_policy. Creating a new policy page is the legacy's other
    # branch; here selection is the reproduced path (a page is authored through the
    # editor track, then chosen here).
    def update_privacy
      page_id = params[:page_for_privacy_policy].to_s
      if page_id.blank? || page_id == "0"
        Configuration::Setting.set("wp_page_for_privacy_policy", 0)
        notice = "Privacy Policy page removed."
      else
        Configuration::Setting.set("wp_page_for_privacy_policy", page_id.to_i)
        notice = "Privacy Policy page updated successfully."
      end
      redirect_after_submit(settings_path_for("privacy"), notice: notice)
    end

    # options-connectors — AI provider configuration, the `Assistance` context
    # (target_screens.md:542), scheduled for Wave 5. The screen exists and is honest
    # about that; it stores nothing yet.
    def update_connectors
      redirect_after_submit(settings_path_for("connectors"), notice: SAVED_NOTICE)
    end

    def settings_path_for(section)
      section == "general" ? "/console/settings" : "/console/settings/#{section}"
    end
    helper_method :settings_path_for

    # ── View data ────────────────────────────────────────────────────────────────
    def current(name) = Configuration::SettingsRegistry.current(name)
    helper_method :current

    def on?(name)
      %w[1 true yes on].include?(current(name).to_s)
    end
    helper_method :on?

    # The value for a text input. For the two options WordPress escapes on write
    # (blogname/blogdescription) the stored form is ALREADY HTML-escaped, and `esc_attr`
    # does not double-encode it (formatting.php) — so it is emitted as-is into the
    # attribute, where the browser decodes it back to the title the user typed. Every
    # other option is raw at rest and gets normal attribute escaping.
    def input_value(name)
      if Configuration::Setting::SANITIZED_ON_WRITE.include?(name)
        Configuration::Setting.display(name).to_s.presence || Configuration::SettingsRegistry.current(name)
      else
        current(name)
      end
    end
    helper_method :input_value

    # `wp_dropdown_roles()`. The five built-in roles are the catalogue's, most-privileged
    # last as the legacy prints them (editable_roles order).
    def selectable_roles
      %w[subscriber contributor author editor administrator]
    end
    helper_method :selectable_roles

    # `wp_dropdown_categories()` over the category taxonomy — id => name.
    def selectable_categories
      Classification::Term.joins(:taxonomy)
                          .where(taxonomies: { name: "category" })
                          .order(:name)
    rescue ActiveRecord::StatementInvalid
      []
    end
    helper_method :selectable_categories

    # `wp_dropdown_pages()` — published pages, for the front-page and privacy selects.
    def selectable_pages
      Publishing::Page.published.order(:title)
    rescue ActiveRecord::StatementInvalid
      []
    end
    helper_method :selectable_pages

    # The five common permalink presets (options-permalink.php:243), example-rendered
    # against the current site. Value is the structure the preset writes.
    def permalink_presets
      home = site_url
      [
        ["Plain",        "",                              "#{home}/?p=123"],
        ["Day and name", "/%year%/%monthnum%/%day%/%postname%/", "#{home}/#{Time.current.strftime("%Y/%m/%d")}/sample-post/"],
        ["Month and name", "/%year%/%monthnum%/%postname%/", "#{home}/#{Time.current.strftime("%Y/%m")}/sample-post/"],
        ["Numeric",      "/archives/%post_id%",           "#{home}/archives/123"],
        ["Post name",    "/%postname%/",                  "#{home}/sample-post/"],
      ]
    end
    helper_method :permalink_presets
  end
end
