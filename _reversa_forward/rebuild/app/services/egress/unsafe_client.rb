# frozen_string_literal: true

module Egress
  # BC-14 Egress -- the named escape hatch. DEVIATION BR-HTTP-01.
  #
  # The legacy's default was unvalidated and the safe path had to be asked for by name.
  # That is inverted here, and this class is the whole inversion: the unvalidated path
  # still exists, because loopback self-requests and operator tooling need it, but a
  # caller can only reach it by writing `Egress::UnsafeClient` at the call site.
  #
  # Two properties the legacy's `wp_remote_get()` did not have:
  #   1. it is greppable -- see the "exactly one validating door" scenario in
  #      spec/parity/features/11-egress-and-ssrf.feature, which fails the build if any
  #      file outside app/services/egress reaches a socket without naming this class;
  #   2. every use is recorded, so "who bypassed the policy, for what" is answerable
  #      after the fact rather than by code review alone.
  class UnsafeClient
    Use = Struct.new(:method, :url, :reason, :at, :call_site, keyword_init: true)

    class << self
      def audit_log = (@audit_log ||= [])
      def clear_audit_log! = audit_log.clear

      def record(use)
        audit_log << use
        Rails.logger&.warn(
          "[egress] UNVALIDATED request #{use.method.to_s.upcase} #{use.url} " \
          "reason=#{use.reason.inspect} at=#{use.call_site}"
        )
        use
      end
    end

    def initialize(transport: Client::NetHttpTransport.new, reason: nil)
      @transport = transport
      @reason = reason
    end

    def get(url, headers: {}) = request(:get, url, headers: headers)
    def post(url, body: nil, headers: {}) = request(:post, url, headers: headers, body: body)

    # No UrlPolicy. That is the point, and it is why the use is written down.
    def request(method, url, headers: {}, body: nil)
      self.class.record(Use.new(method: method, url: url, reason: @reason,
                                at: Time.current, call_site: call_site))
      response = @transport.call(method: method, url: url, headers: headers, body: body)
      response.is_a?(Client::Response) ? response : Client::Response.new(**response.to_h)
    end

    private

    # The frame that matters is the one that CHOSE the unsafe path, not `#get` calling
    # `#request` one line down. Skip our own file.
    def call_site
      own_directory = __dir__
      frame = caller_locations(2, 32)&.find { |l| File.dirname(l.absolute_path.to_s) != own_directory }
      frame.to_s
    end
  end
end
