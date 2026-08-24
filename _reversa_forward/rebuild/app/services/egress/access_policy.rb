# frozen_string_literal: true

module Egress
  # BR-MIGRATE-257 (BR-HTTP-13). Legacy: WP_Http::block_request(), class-wp-http.php:895.
  #
  # A site-wide egress allowlist, SEPARATE from the SSRF address check (UrlPolicy). The
  # legacy gate is off unless the deployment defines WP_HTTP_BLOCK_EXTERNAL; when it is on,
  # everything is blocked EXCEPT the site's own host, `localhost`, and the hosts named in
  # WP_ACCESSIBLE_HOSTS (a comma list, `*` wildcards supported).
  #
  # What is reproduced vs. absorbed:
  #   * the MATCHING BEHAVIOUR -- own-host/localhost bypass, the comma split, the
  #     wildcard-to-regex translation, and the inverse "in the list ⇒ allow" logic -- is
  #     reproduced here byte-for-byte from block_request().
  #   * the SOURCE of the switch is a deployment constant in the legacy (wp-config.php);
  #     Rails owns deployment configuration, so it is read from the environment
  #     (`.from_env`) instead of a PHP `define()`. Same values, different dialect.
  #
  # AD-01: block_request() consults the `block_local_requests` filter for the own-host
  # case; its pre-filter default is false ("do not block local"), so the own-host bypass
  # is unconditional here -- there is no filter to flip it.
  #
  # DEFAULT-OFF, exactly as the legacy: an unset WP_HTTP_BLOCK_EXTERNAL means `block?`
  # is always false, so with no configuration this class changes nothing (the SSRF check
  # in UrlPolicy remains the only gate). That is why `Client` defaults to `disabled`.
  class AccessPolicy
    # `localhost` is always allowed alongside the site's own host (class-wp-http.php:908).
    LOCALHOST = "localhost"

    class << self
      # The legacy default: WP_HTTP_BLOCK_EXTERNAL undefined ⇒ nothing is blocked.
      def disabled = new(blocked: false)

      # Reads the deployment switches from the environment, the Rails-native equivalent of
      # the wp-config.php `define()`s. WP_HTTP_BLOCK_EXTERNAL is truthy for "1"/"true";
      # WP_ACCESSIBLE_HOSTS is the raw comma list (nil when the constant is not defined).
      def from_env(env: ENV, site_host: default_site_host)
        raw = env["WP_HTTP_BLOCK_EXTERNAL"].to_s.strip.downcase
        blocked = %w[1 true yes on].include?(raw)
        accessible = env.key?("WP_ACCESSIBLE_HOSTS") ? env["WP_ACCESSIBLE_HOSTS"] : nil
        new(blocked: blocked, accessible_hosts: accessible, site_host: site_host)
      end

      # block_request() reads get_option('siteurl') for the own-host comparison.
      def default_site_host
        value = Configuration::Setting["siteurl"]
        return nil unless value.is_a?(String) && !value.empty?

        URI.parse(value).host
      rescue URI::InvalidURIError
        nil
      end
    end

    def initialize(blocked:, accessible_hosts: nil, site_host: nil)
      @blocked = blocked
      # nil means "WP_ACCESSIBLE_HOSTS not defined"; a string is the raw comma list.
      @accessible_hosts_raw = accessible_hosts
      @site_host = site_host
    end

    # True to block, false to allow -- the exact contract and branch order of
    # block_request($uri). Returns for a given, already-SSRF-validated URL.
    def block?(url)
      # "We don't need to block requests, because nothing is blocked." (line 897)
      return false unless @blocked

      host = host_of(url)
      # `if ( ! $check ) return true;` -- an unparseable URL is blocked.
      return true if host.nil? || host.empty?

      # Own host or localhost: `block_local_requests` default false ⇒ do not block.
      return false if host == LOCALHOST
      return false if @site_host && host.casecmp?(@site_host)

      # `if ( ! defined( 'WP_ACCESSIBLE_HOSTS' ) ) return true;` -- blocked with no list.
      return true if @accessible_hosts_raw.nil?

      if @accessible_hosts_raw.include?("*")
        # Inverse logic: allowed when the wildcard regex matches, blocked otherwise.
        !wildcard_regex.match?(host)
      else
        # Inverse logic: allowed when the host is in the list, blocked otherwise.
        !accessible_hosts.include?(host)
      end
    end

    private

    # `preg_split( '|,\s*|', WP_ACCESSIBLE_HOSTS )` -- comma, then any trailing whitespace.
    def accessible_hosts
      @accessible_hosts ||= @accessible_hosts_raw.split(/,\s*/)
    end

    # `str_replace( '\*', '.+', preg_quote( $host, '/' ) )` for each host, joined with `|`,
    # anchored and case-insensitive -- so `*.wordpress.org` matches any subdomain.
    def wildcard_regex
      @wildcard_regex ||= begin
        alternation = accessible_hosts.map { |h| Regexp.escape(h).gsub('\*', ".+") }.join("|")
        /\A(#{alternation})\z/i
      end
    end

    def host_of(url)
      URI.parse(url).host
    rescue URI::InvalidURIError
      nil
    end
  end
end
