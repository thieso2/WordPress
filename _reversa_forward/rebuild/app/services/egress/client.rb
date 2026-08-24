# frozen_string_literal: true

module Egress
  # BC-14 Egress -- the one door. BR-MIGRATE-245 (DEVIATION BR-HTTP-01),
  # BR-MIGRATE-256 (transport selection), BR-MIGRATE-257 (site-wide allowlist).
  #
  # target_architecture.md, BC-14: "In the legacy, SSRF validation is opt-in by function
  # name -- wp_safe_remote_get() validates, wp_remote_get() does not (F-HTTP-05). Here
  # there is one door, it validates, and the unsafe path is an explicit named escape
  # hatch."
  #
  # So: this class always validates, before the transport is touched at all, and it
  # re-validates every redirect hop (WP_Http::validate_redirects(),
  # class-wp-http.php:530 -- which in the legacy only runs when the caller opted in).
  class Client
    # BR-MIGRATE-256 (BR-HTTP-12): the legacy picks between cURL and streams per request
    # based on capability requirements. Rails deployments have one HTTP stack, so the
    # per-request negotiation is a mechanism the framework replaces; what survives is
    # that the transport is a replaceable collaborator with a stated contract.
    # It exists as a seam for the same reason the resolver does: so the parity suite can
    # prove the refusal happened WITHOUT a connection.
    Response = Struct.new(:status, :headers, :body, :url, keyword_init: true) do
      def success? = status.between?(200, 299)
      # HTTP header names are case-insensitive and the transports disagree about case.
      def header(name) = headers.to_h.transform_keys { |k| k.to_s.downcase }[name.to_s.downcase]
      def location = header("location")
      def redirect? = status.between?(300, 399) && location.present?
    end

    # BR-MIGRATE-255-adjacent: the legacy's default redirection count is 5
    # (class-wp-http.php:191, pre-filter default).
    MAX_REDIRECTS = 5

    class TooManyRedirects < StandardError
      def initialize = super("Too many redirects.")
    end

    # BR-MIGRATE-257 (BR-HTTP-13): the site-wide egress allowlist refused the target.
    # Distinct from UrlPolicy::Refused (the SSRF address check) -- this is the deployment
    # deciding no external host may be reached except an allowlisted one. Legacy
    # equivalent: the WP_Error('http_request_not_executed') WP_Http::request() returns
    # when block_request() is true (class-wp-http.php:303). Rule 4, no copy editing: the
    # code and the sprintf'd message are the legacy's, verbatim.
    class Blocked < StandardError
      ERROR_CODE = "http_request_not_executed"

      attr_reader :url

      def initialize(url)
        @url = url
        super("User has blocked requests through HTTP to the URL: #{url}.")
      end

      def error_code = ERROR_CODE
    end

    # Net::HTTP, wrapped to the transport contract. Never reached in the parity suite --
    # every scenario supplies its own transport, which is how "refused before any
    # connection is made" is observable at all.
    class NetHttpTransport
      def call(method:, url:, headers:, body:)
        require "net/http"
        uri = URI.parse(url)
        request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
        headers.each { |k, v| request[k] = v }
        request.body = body if body
        response = Net::HTTP.start(uri.hostname, uri.port,
                                   use_ssl: uri.scheme == "https") { |http| http.request(request) }
        Response.new(status: response.code.to_i, url: url, body: response.body,
                     headers: response.each_header.to_h)
      end
    end

    def initialize(transport: NetHttpTransport.new, resolver: UrlPolicy::SYSTEM_RESOLVER,
                   home_url: nil, max_redirects: MAX_REDIRECTS, access_policy: AccessPolicy.disabled)
      @transport = transport
      @resolver = resolver
      @home_url = home_url
      @max_redirects = max_redirects
      # BR-MIGRATE-257 (BR-HTTP-13): default-off, exactly as WP_HTTP_BLOCK_EXTERNAL is
      # undefined by default, so this changes nothing unless a deployment opts in.
      @access_policy = access_policy
    end

    def get(url, headers: {}) = request(:get, url, headers: headers)
    def head(url, headers: {}) = request(:head, url, headers: headers)
    def post(url, body: nil, headers: {}) = request(:post, url, headers: headers, body: body)

    # Raises Egress::UrlPolicy::Refused before the transport is consulted. There is no
    # argument that turns this off -- AD-01 removed the filter that used to, and
    # BR-HTTP-01's deviation removed the opt-in that used to gate it.
    def request(method, url, headers: {}, body: nil)
      target = validate(url)
      remaining = @max_redirects

      loop do
        response = @transport.call(method: method, url: target, headers: headers, body: body)
        response = Response.new(**response.to_h) unless response.is_a?(Response)
        return response unless response.redirect?

        raise TooManyRedirects if remaining <= 0

        remaining -= 1
        # Every hop goes back through the same door. In the legacy this check lives in
        # WP_Http::validate_redirects() and is only wired up when reject_unsafe_urls was
        # set; here there is no version of the request that skips it.
        target = validate(absolute_url(response.location, target))
        # POST is not re-POSTed to a redirect target (class-wp-http.php:1082).
        method = :get if method == :post
      end
    end

    # The address is SSRF-validated first (UrlPolicy), then run past the site-wide egress
    # allowlist (AccessPolicy) -- the same two-stage gate WP_Http::request() applies:
    # wp_http_validate_url() then block_request(). Both run on every redirect hop.
    def validate(url)
      target = UrlPolicy.validate!(url, resolver: @resolver, home_url: @home_url)
      raise Blocked.new(target) if @access_policy.block?(target)

      target
    end

    private

    def absolute_url(location, base)
      URI.join(base, location).to_s
    rescue URI::Error, ArgumentError
      location.to_s
    end
  end
end
