# frozen_string_literal: true

module Egress
  # BC-14 Egress -- BR-MIGRATE-246..255 (BR-HTTP-02..11).
  # Legacy: wp_http_validate_url(), wp-includes/http.php:559.
  #
  # ⚠️ DEVIATION BR-HTTP-01 (approved, parity_specs.md). In the legacy this function is
  # reached ONLY when the caller opted in -- `wp_safe_remote_get()` sets
  # `reject_unsafe_urls`, `wp_remote_get()` does not (F-HTTP-05, class-wp-http.php:284).
  # Here the policy is unconditional: `Egress::Client` consults it on every request and
  # on every redirect hop, and the only way past it is `Egress::UnsafeClient`, which says
  # so in its name.
  #
  # AD-01: every `apply_filters()` in the legacy body is implemented at its PRE-FILTER
  # default and there is no way to change it --
  #   * `http_request_host_is_external` (BR-MIGRATE-253) defaults to false, so a blocked
  #     range is simply blocked;
  #   * `http_allowed_safe_ports`      (BR-MIGRATE-254) defaults to 80, 443, 8080.
  class UrlPolicy
    # BR-MIGRATE-246 (BR-HTTP-02): only http and https are accepted.
    ALLOWED_SCHEMES = %w[http https].freeze

    # BR-MIGRATE-254 (BR-HTTP-10): with an explicit port, only these three.
    ALLOWED_PORTS = [80, 443, 8080].freeze

    # BR-MIGRATE-249 (BR-HTTP-05): a host containing any of these is rejected. This is
    # what excludes IPv6 literals entirely -- `[::1]` carries all three of `[`, `]`, `:`.
    FORBIDDEN_HOST_CHARACTERS = ":#?[]"

    # A dotted-quad, matched exactly as the legacy's inline pattern does -- so a host that
    # merely looks numeric is still sent to the resolver.
    DOTTED_QUAD = /\A(([1-9]?\d|1\d\d|25[0-5]|2[0-4]\d)\.){3}([1-9]?\d|1\d\d|25[0-5]|2[0-4]\d)\z/

    # Raised instead of returning false. The legacy returns `false` from
    # wp_http_validate_url() and the caller decides; here refusal is the only outcome a
    # caller can get, so it is an exception and it carries why.
    class Refused < StandardError
      attr_reader :url, :reason

      def initialize(url, reason)
        @url = url
        @reason = reason
        super("A valid URL was not provided.")
      end
    end

    # gethostbyname() in the legacy (BR-MIGRATE-251). Isolated behind a callable so the
    # parity suite can answer DNS without a network, exactly as the transport is isolated
    # in Egress::Client. This is an I/O seam, not an extension point: there is no
    # registry, no priority and no chaining.
    SYSTEM_RESOLVER = lambda do |host|
      require "resolv"
      begin
        Resolv.getaddress(host)
      rescue Resolv::ResolvError, Resolv::ResolvTimeout
        # gethostbyname() signals failure by handing the input back unchanged.
        host
      end
    end

    class << self
      def validate!(url, resolver: SYSTEM_RESOLVER, home_url: nil)
        new(url, resolver: resolver, home_url: home_url).validate!
      end

      def permitted?(url, resolver: SYSTEM_RESOLVER, home_url: nil)
        new(url, resolver: resolver, home_url: home_url).permitted?
      end

      # The nearest thing to the legacy's return contract: the accepted URL, or nil.
      def validate(url, resolver: SYSTEM_RESOLVER, home_url: nil)
        validate!(url, resolver: resolver, home_url: home_url)
      rescue Refused
        nil
      end

      def refusal_reason(url, resolver: SYSTEM_RESOLVER, home_url: nil)
        validate!(url, resolver: resolver, home_url: home_url)
        nil
      rescue Refused => e
        e.reason
      end
    end

    def initialize(url, resolver: SYSTEM_RESOLVER, home_url: nil)
      @url = url
      @resolver = resolver
      @home_url = home_url
    end

    def permitted?
      validate!
      true
    rescue Refused
      false
    end

    # Returns the accepted URL -- which, exactly as in the legacy, is the value KSES
    # handed back, not the caller's original string.
    def validate!
      refuse(:not_a_url) unless @url.is_a?(String)
      refuse(:not_a_url) if @url.empty?
      # `is_numeric($url)` -- http.php:560.
      refuse(:not_a_url) if numeric?(@url)

      sanitized = sanitized_url
      parsed = parse(sanitized)

      refuse(:no_host) if parsed.host.nil? || parsed.host.empty?
      # BR-MIGRATE-248 (BR-HTTP-04).
      refuse(:userinfo) if parsed.userinfo
      # BR-MIGRATE-249 (BR-HTTP-05).
      refuse(:forbidden_host_character) if parsed.host.count(FORBIDDEN_HOST_CHARACTERS).positive?

      host = parsed.host.gsub(/\A\.+|\.+\z/, "")

      # BR-MIGRATE-250 (BR-HTTP-06): the site's own host bypasses every IP-range check,
      # so a loopback self-request still works.
      check_address(host, sanitized) unless same_host?(parsed.host)
      check_port(parsed, sanitized)

      sanitized
    end

    private

    def refuse(reason) = raise(Refused.new(@url, reason))

    def numeric?(value)
      # PHP's is_numeric: leading whitespace allowed, integers, floats, hex-free.
      value.match?(/\A\s*[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?\s*\z/)
    end

    # BR-MIGRATE-247 (BR-HTTP-03): sanitization used as DETECTION. If KSES's protocol
    # filter changes the URL in any way other than letter case, the URL is refused rather
    # than corrected. The pack does the work, so the detection is the legacy's own.
    def sanitized_url
      cleaned = Sanitizing::Kses.wp_kses_bad_protocol(@url, ALLOWED_SCHEMES)
      cleaned = cleaned.to_s.dup.force_encoding(Encoding::UTF_8)
      refuse(:rejected_by_sanitizer) if cleaned.empty?
      refuse(:altered_by_sanitizer) unless cleaned.downcase == @url.downcase
      cleaned
    end

    # Recovers host / userinfo / port the way PHP's parse_url() does. The legacy reads
    # ONLY those three components (http.php:569-577, 641), and parse_url() extracts them
    # from the authority without caring what the path, query or fragment contain -- a
    # space in the path (`http://8.8.8.8/pa th`) is host 8.8.8.8 to parse_url() but a
    # fatal URI::InvalidURIError to Ruby's stricter URI.parse. So isolate the authority
    # exactly as parse_url does -- between the "//" and the next "/", "?" or "#" -- and
    # let URI parse a synthetic URL whose path is empty, keeping the well-tested
    # authority parsing (userinfo, IPv6 brackets, port) while nothing downstream of the
    # authority can make parsing fail.
    def parse(value)
      m = value.match(%r{\A([a-zA-Z][a-zA-Z0-9+.\-]*:)?//([^/?#]*)})
      if m
        # A protocol-relative URL (`//host/x`) has no scheme; parse_url() still finds the
        # host, so give URI a throwaway scheme purely so it treats the string as authority.
        scheme = m[1] || "http:"
        URI.parse("#{scheme}//#{m[2]}/")
      else
        URI.parse(value)
      end
    rescue URI::InvalidURIError
      refuse(:unparseable)
    end

    def same_host?(host)
      home = home_host
      home.present? && home.downcase == host.downcase
    end

    def home_host
      @home_host ||= begin
        value = @home_url || Configuration::Setting["home"]
        value.is_a?(String) && !value.empty? ? (URI.parse(value).host rescue nil) : nil
      end
    end

    def home_port
      @home_port ||= begin
        value = @home_url || Configuration::Setting["home"]
        value.is_a?(String) && !value.empty? ? (URI.parse(value).port rescue nil) : nil
      end
    end

    def check_address(host, _url)
      if host.match?(DOTTED_QUAD)
        ip = host
      else
        ip = @resolver.call(host)
        # BR-MIGRATE-251 (BR-HTTP-07): the resolver handing back its own input is
        # gethostbyname()'s failure signal, and a failure to resolve is a refusal.
        refuse(:unresolvable) if ip.nil? || ip == host
      end
      return if ip.nil? || ip.empty?

      # BR-MIGRATE-252 (BR-HTTP-08): 13 blocked IPv4 ranges. The filter that could
      # re-permit one of them (BR-MIGRATE-253) defaults to false and does not exist here,
      # so a blocked range is final.
      refuse(:blocked_address_range) if blocked_range?(ip)
    end

    def blocked_range?(ip)
      parts = ip.split(".").map(&:to_i)
      return false unless parts.length == 4

      a, b, c, _d = parts
      a == 127 ||                       # 127.0.0.0/8    loopback
        a == 10 ||                      # 10.0.0.0/8     private
        a.zero? ||                      # 0.0.0.0/8      this network
        (a == 172 && b.between?(16, 31)) ||  # 172.16.0.0/12   private
        (a == 192 && b == 168) ||            # 192.168.0.0/16  private
        (a == 192 && b.zero? && c.zero?) ||  # 192.0.0.0/24    IETF protocol assignments
        (a == 192 && b.zero? && c == 2) ||   # 192.0.2.0/24    TEST-NET-1
        (a == 192 && b == 88 && c == 99) ||  # 192.88.99.0/24  6to4 relay anycast
        (a == 198 && b == 51 && c == 100) || # 198.51.100.0/24 TEST-NET-2
        (a == 203 && b.zero? && c == 113) || # 203.0.113.0/24  TEST-NET-3
        (a == 169 && b == 254) ||            # 169.254.0.0/16  link-local AND CLOUD METADATA
        (a == 100 && b.between?(64, 127)) || # 100.64.0.0/10   CGNAT
        (a == 198 && b.between?(18, 19)) ||  # 198.18.0.0/15   benchmarking
        a.between?(224, 239) ||              # 224.0.0.0/4     multicast
        a >= 240                             # 240.0.0.0/4     reserved, incl. broadcast
    end

    # The legacy gate is `empty( $parsed_url['port'] )` (http.php:641), and PHP's empty()
    # is true for the integer 0 -- so wp_http_validate_url('http://8.8.8.8:0/') and
    # ':00' RETURN THE URL, confirmed against the running oracle. Port 0 is therefore
    # treated exactly as "no explicit port": it passes the port check unconditionally,
    # matching parse_url()+empty(). (Reproduced verbatim rather than left to fail closed,
    # so the differential corpus verdicts are identical; see url_policy_differential_spec.)
    def check_port(parsed, url)
      port = explicit_port(url)
      # BR-MIGRATE-255 (BR-HTTP-11): no explicit port -- and, per empty(), port 0 -- pass.
      return if port.nil? || port.zero?
      return if ALLOWED_PORTS.include?(port)
      # The legacy's last resort: the site's own host on the site's own port.
      return if same_host?(parsed.host) && home_port == port

      refuse(:port_not_allowed)
    end

    # parse_url()'s `port` key is absent unless the authority actually carried one; URI
    # substitutes the scheme default, which would make BR-MIGRATE-255 unobservable.
    def explicit_port(url)
      authority = url[%r{\A[a-zA-Z][a-zA-Z0-9+.\-]*://([^/?#]*)}, 1]
      return nil if authority.nil?

      match = authority[/:(\d*)\z/, 1]
      return nil if match.nil? || match.empty?

      match.to_i
    end
  end
end
