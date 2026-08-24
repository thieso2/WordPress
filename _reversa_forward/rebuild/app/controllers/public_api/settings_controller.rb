# frozen_string_literal: true

module PublicApi
  # /wp/v2/settings — WP_REST_Settings_Controller.
  #
  # The site settings the block editor reads at boot (date/time formats, the front-page
  # wiring, the default comment status a new post inherits). One route, two methods; the
  # SET is `register_initial_settings()` (wp-includes/option.php:2742) plus the two
  # `site_logo`/`site_icon` registrations in wp-includes/theme.php — DECLARED here rather
  # than hooked, exactly as SchemaRegistry declares the post types (AD-01: `register_setting`
  # is not a hook system, it is a list, and this is that list).
  #
  # ⚠️ Both methods gate on `manage_options` (WP_REST_Settings_Controller::
  # get_item_permissions_check → `current_user_can( 'manage_options' )`). The oracle answers
  # an anonymous GET with the GENERIC `rest_forbidden` 401, not a settings-specific code —
  # verified, and reproduced by returning false from the callback so BaseController's
  # BR-REST-04 arm builds it.
  #
  # BR-CAP-05: the capability question is asked HERE, in the controller, and nowhere else.
  class SettingsController < BaseController
    permission :show, :manage_options?
    permission :update, :manage_options?

    # ── register_initial_settings(), in registration order ────────────────────────────
    # The response's key order IS this order; the oracle emits it and Gutenberg's
    # `getEntityRecord( 'root', 'site' )` reads it by name.
    #
    # `option` is the name in Configuration::Setting, `type` the JSON-Schema type the
    # value is prepared as, `default` what `get_option( $name, $default )` falls back to
    # when the row is absent.
    Setting = Struct.new(:name, :option, :type, :default, :enum, keyword_init: true)

    REGISTERED = [
      Setting.new(name: "title",                  option: "blogname",               type: :string),
      Setting.new(name: "description",            option: "blogdescription",        type: :string),
      # Both are wrapped in `if ( ! is_multisite() )` (option.php:2770, :2787). Tenancy is
      # off by default here, and Tenancy.enabled? is the same switch.
      Setting.new(name: "url",                    option: "siteurl",                type: :string),
      Setting.new(name: "email",                  option: "admin_email",            type: :string),
      Setting.new(name: "timezone",               option: "timezone_string",        type: :string),
      Setting.new(name: "date_format",            option: "date_format",            type: :string),
      Setting.new(name: "time_format",            option: "time_format",            type: :string),
      Setting.new(name: "start_of_week",          option: "start_of_week",          type: :integer),
      Setting.new(name: "language",               option: "WPLANG",                 type: :string,  default: "en_US"),
      Setting.new(name: "use_smilies",            option: "use_smilies",            type: :boolean, default: true),
      Setting.new(name: "default_category",       option: "default_category",       type: :integer),
      Setting.new(name: "default_post_format",    option: "default_post_format",    type: :string),
      Setting.new(name: "posts_per_page",         option: "posts_per_page",         type: :integer, default: 10),
      Setting.new(name: "show_on_front",          option: "show_on_front",          type: :string),
      Setting.new(name: "page_on_front",          option: "page_on_front",          type: :integer),
      Setting.new(name: "page_for_posts",         option: "page_for_posts",         type: :integer),
      Setting.new(name: "default_ping_status",    option: "default_ping_status",    type: :string, enum: %w[open closed]),
      Setting.new(name: "default_comment_status", option: "default_comment_status", type: :string, enum: %w[open closed]),
      # theme.php's two: `site_logo` has NO default, so an unset one is null — the one
      # nullable member of the set, and the oracle emits exactly that.
      Setting.new(name: "site_logo",              option: "site_logo",              type: :integer_or_null),
      Setting.new(name: "site_icon",              option: "site_icon",              type: :integer, default: 0)
    ].freeze

    BY_NAME = REGISTERED.index_by(&:name).freeze

    SANITIZED_ON_WRITE = Configuration::Setting::SANITIZED_ON_WRITE

    def show
      render_json(document)
    end

    # PUT/PATCH/POST /wp/v2/settings — WP_REST_Settings_Controller::update_item(). Only
    # the names present in the body are written; everything else is left alone. A value
    # that fails its type is `rest_invalid_param` 400 with the per-parameter `details`
    # block the oracle emits, and NOTHING is written — the whole request is rejected
    # before the first write, which is what makes a bad field harmless.
    def update
      body = request_body
      writes = {}
      invalid = {}

      body.each do |key, raw|
        setting = BY_NAME[key.to_s]
        next if setting.nil? # an unregistered name is ignored, not an error.

        begin
          writes[setting] = coerce(setting, raw)
        rescue TypeMismatch => e
          invalid[setting.name] = e.message
        end
      end

      raise invalid_params(invalid) if invalid.any?

      # AD-05: one transaction, so a failure mid-way leaves no half-applied settings.
      Configuration::Setting.transaction do
        writes.each do |setting, value|
          if value.nil?
            # WP_REST_Settings_Controller::update_item(): "A null value for an option
            # means it should be deleted." (:174)
            Configuration::Setting.where(name: setting.option).delete_all
          else
            Configuration::Setting.set(setting.option, value)
          end
        end
      end

      render_json(document)
    end

    private

    def manage_options? = current_actor && Access::SettingPolicy.new(current_actor, nil).permit?(:edit)

    def document
      REGISTERED.to_h { |setting| [setting.name, read(setting)] }
    end

    # `get_option( $name, $args['schema']['default'] )` then `prepare_value()`, which
    # runs the value through the setting's schema.
    def read(setting)
      record = Configuration::Setting.find_by(name: setting.option)
      return setting.default if record.nil?

      prepare(setting, record.value)
    end

    def prepare(setting, value)
      case setting.type
      when :integer then value.to_i
      when :integer_or_null then value.nil? || value.to_s.empty? ? nil : value.to_i
      when :boolean then truthy?(value)
      else value.to_s
      end
    end

    # rest_sanitize_boolean(): '0', '', 'false' and 0 are false, everything else true.
    def truthy?(value)
      return value if value == true || value == false

      !%w[0 false].include?(value.to_s.strip.downcase) && !value.to_s.strip.empty?
    end

    class TypeMismatch < StandardError; end

    # rest_validate_value_from_schema(), the two arms this set can trip: a wrong JSON
    # type, and a value outside an `enum`. Both messages are the oracle's, verbatim.
    def coerce(setting, raw)
      return nil if raw.nil?

      case setting.type
      when :integer, :integer_or_null
        raise TypeMismatch, "#{setting.name} is not of type integer." unless integerish?(raw)

        # ⚠️ An INTEGER, not the numeral as a string. Configuration::SettingsRegistry casts
        # these same names to Integer when the console's settings screens write them
        # (`f("page_on_front", :integer, 0)`), and Access::PostPolicy compares
        # `page_on_front` to a record id. Two writers producing two types for one option is
        # exactly the drift a typed registry exists to prevent, so this one matches it.
        raw.to_i
      when :boolean
        raise TypeMismatch, "#{setting.name} is not of type boolean." unless boolish?(raw)

        truthy?(raw) ? "1" : "0"
      else
        raise TypeMismatch, "#{setting.name} is not of type string." unless raw.is_a?(String) || raw.is_a?(Numeric)

        value = raw.to_s
        if setting.enum && !setting.enum.include?(value)
          raise TypeMismatch, "#{setting.name} is not one of #{setting.enum.join(", ")}."
        end

        # BR-MIGRATE-014 (BR-OPT-15): `update_option()` runs `sanitize_option()`, and for
        # blogname/blogdescription that arm is `esc_html`. Configuration::Setting stores
        # those two ALREADY ESCAPED (SANITIZED_ON_WRITE), so a value written through this
        # endpoint has to arrive in the same state or the front end would render a raw
        # quote where the console renders an entity. esc_html does not double-encode, so
        # writing back what GET returned is a no-op — verified against the oracle.
        value = Configuration::SettingsRegistry::ESC_HTML.call(value) if SANITIZED_ON_WRITE.include?(setting.option)
        value
      end
    end

    def integerish?(raw)
      return true if raw.is_a?(Integer)
      return raw == raw.to_i if raw.is_a?(Float)

      raw.is_a?(String) && raw.match?(/\A-?\d+\z/)
    end

    def boolish?(raw)
      [true, false, 0, 1, "0", "1", "true", "false", ""].include?(raw)
    end

    # rest_invalid_param, class-wp-rest-request.php:945 — the `params` map is
    # name => message, and `details` carries the full per-parameter WP_Error.
    def invalid_params(invalid)
      details = invalid.to_h do |name, message|
        [name, { code: "rest_invalid_type", message: message, data: { param: name } }]
      end
      PublicApi::RestError.new(
        "rest_invalid_param",
        "Invalid parameter(s): #{invalid.keys.join(", ")}",
        400,
        { params: invalid, details: details }
      )
    end

    # The REST server parses a JSON body into the request's params; Rails puts it in
    # `request.request_parameters` for a JSON content type and leaves it raw otherwise.
    def request_body
      parsed = request.request_parameters
      return parsed if parsed.is_a?(Hash) && parsed.any?

      raw = request.raw_post.to_s
      return {} if raw.empty?

      decoded = begin
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end
      decoded.is_a?(Hash) ? decoded : {}
    end
  end
end
