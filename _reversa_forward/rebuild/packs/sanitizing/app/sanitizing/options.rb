# frozen_string_literal: true

module Sanitizing
  # Per-option sanitization.
  #
  # BR-MIGRATE-297 (BR-FMT-07): sanitize_option() dispatches per option name and
  # is applied on every option write.
  # Legacy: sanitize_option(), wp-includes/formatting.php:4933.
  #
  # ⚠️ Partial by construction. The legacy switch mixes pure string work with
  # calls that need the database ($wpdb->strip_invalid_text_for_column),
  # the current option value (get_option), the role registry (get_role), the
  # site's language list (get_available_languages) and PHP's timezone database.
  # This pack declares zero dependencies (topology_decision.md option 3), so the
  # branches needing site state are reported back to the caller instead of being
  # faked. See README, "sanitize_option".
  #
  # AD-01: the `sanitize_option_{$option}` filter has no analogue.
  # RISK-008: the legacy comments about "strips slashes" describe what
  # wp_magic_quotes() had already done to the input. Rails params are never
  # slashed, so those branches simply do their own work here.
  module Options
    # Options sanitized to a non-negative integer. wp-includes/formatting.php:4959.
    ABSINT_OPTIONS = %w[
      thumbnail_size_w thumbnail_size_h medium_size_w medium_size_h
      medium_large_size_w medium_large_size_h large_size_w large_size_h
      mailserver_port comment_max_links page_on_front page_for_posts
      rss_excerpt_length default_category default_email_category
      default_link_category close_comments_days_old comments_per_page
      thread_comments_depth users_can_register start_of_week site_icon
      fileupload_maxk
    ].freeze

    # wp-includes/formatting.php:5031 — stripped of tags, then run through kses.
    KSES_DATA_OPTIONS = %w[
      date_format time_format mailserver_url mailserver_login mailserver_pass
      upload_path
    ].freeze

    # Branches this pack cannot decide on its own. wp-includes/formatting.php:5077,
    # :5124, :5155, :5159.
    NEEDS_SITE_STATE = %w[
      admin_email new_admin_email WPLANG timezone_string default_role
    ].freeze

    # A branch that needed site state. The caller resolves it; the pack does not
    # guess. `error` carries the legacy message verbatim where there is one.
    Deferred = Struct.new(:option, :value, :reason, :error)

    module_function

    # BR-MIGRATE-297 (BR-FMT-07) — Legacy: sanitize_option(),
    # wp-includes/formatting.php:4933.
    def sanitize_option(option, value)
      return Deferred.new(option, value, :needs_site_state, nil) if NEEDS_SITE_STATE.include?(option)

      case option
      when *ABSINT_OPTIONS
        absint(value)
      when 'posts_per_page', 'posts_per_rss'
        v = to_int(value)
        v = 1 if v.zero?
        v = v.abs if v < -1
        v
      when 'default_ping_status', 'default_comment_status'
        # "Options that if not there have 0 value but need to be something like 'closed'."
        (value.to_s == '0' || value.to_s.empty?) ? 'closed' : value
      when 'blogdescription', 'blogname'
        # The legacy round-trips through $wpdb->strip_invalid_text_for_column()
        # to survive utf8 vs utf8mb4; PostgreSQL text has no such truncation
        # (RISK-006), so only the escaping step remains.
        Formatting.esc_html(value)
      when 'blog_charset'
        value.is_a?(String) ? value.gsub(/[^a-zA-Z0-9_-]/, '') : ''
      when 'blog_public'
        value.nil? ? 1 : to_int(value)
      when *KSES_DATA_OPTIONS
        Kses.wp_kses_data(Formatting.strip_tags(value).force_encoding(Encoding::UTF_8))
      when 'ping_sites'
        value.to_s.split("\n", -1).map(&:strip).reject(&:empty?)
             .map { |u| Formatting.sanitize_url(u) }.reject(&:empty?).join("\n")
      when 'gmt_offset'
        numeric?(value) ? value.to_s.gsub(/[^0-9:.-]/, '') : ''
      when 'siteurl', 'home'
        if /http(s?):\/\/(.+)/i.match?(value.to_s)
          Formatting.sanitize_url(value)
        else
          Deferred.new(option, value, :invalid, error_message(option))
        end
      when 'illegal_names'
        list = value.is_a?(Array) ? value : value.to_s.split(' ', -1)
        list = list.map(&:strip).reject(&:empty?)
        list.empty? ? '' : list
      when 'limited_email_domains', 'banned_email_domains'
        list = value.is_a?(Array) ? value : value.to_s.split("\n", -1)
        domains = list.map(&:strip).reject(&:empty?)
        out = domains.select { |d| !/(--|\.\.)/.match?(d) && /\A([a-zA-Z0-9\-.])+\z/.match?(d) }
        out.empty? ? '' : out
      when 'permalink_structure', 'category_base', 'tag_base'
        v = Formatting.sanitize_url(value).sub('http://', '')
        if option == 'permalink_structure' && !v.empty? && !/%[^\/%]+%/.match?(v)
          Deferred.new(option, value, :invalid, PERMALINK_ERROR)
        else
          v
        end
      when 'moderation_keys', 'disallowed_keys'
        value.to_s.split("\n", -1).map(&:strip).reject(&:empty?).uniq.join("\n")
      else
        value
      end
    end

    # Legacy strings, preserved verbatim — no copy editing (handoff.md).
    SITEURL_ERROR = 'The WordPress address you entered did not appear to be a valid URL. Please enter a valid URL.'
    HOME_ERROR = 'The Site address you entered did not appear to be a valid URL. Please enter a valid URL.'
    PERMALINK_ERROR = 'A structure tag is required when using custom permalinks. <a href="%s">Learn more</a>'

    def error_message(option)
      option == 'siteurl' ? SITEURL_ERROR : HOME_ERROR
    end

    # PHP absint() = abs((int) $value).
    def absint(value)
      to_int(value).abs
    end

    # PHP's (int) cast: leading numeric prefix, else 0.
    def to_int(value)
      return value.to_i if value.is_a?(Numeric)
      return value ? 1 : 0 if value == true || value == false

      value.to_s[/\A\s*[+-]?\d+/].to_i
    end

    def numeric?(value)
      return true if value.is_a?(Numeric)

      /\A\s*[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?\s*\z/.match?(value.to_s)
    end
  end
end
