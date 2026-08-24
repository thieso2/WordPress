# frozen_string_literal: true

module Assistance
  # BR-MIGRATE-277 (BR-AI-09): the AI client's HTTP goes through the WordPress HTTP API. The
  # legacy WP_AI_Client_Http_Client (wp-includes/ai-client/adapters/class-wp-ai-client-http-client.php)
  # sends every provider request through `wp_safe_remote_request()` — the SSRF-VALIDATING variant.
  #
  # In the rebuild there is exactly one door for outbound HTTP, and it always validates:
  # Egress::Client (target_architecture.md BC-14, BR-MIGRATE-245). Routing the AI client through
  # it reproduces the observable guarantee that mattered — a provider URL that resolves to a
  # blocked address is refused BEFORE any connection is made, with no per-call opt-in to turn the
  # check off (AD-01 removed the filter that could, BR-HTTP-01's deviation removed the opt-in that
  # gated it). The PSR-18 adapter machinery, the transport negotiation, and the response-factory
  # plumbing are all mechanism the framework absorbs; what survives is "provider HTTP is validated
  # egress".
  #
  # The Egress::Client is injected, defaulting to a fresh validating client. Specs supply a client
  # with a stub transport, so the pipeline is proven WITHOUT any real provider call or network I/O.
  class AiClient
    def initialize(egress: Egress::Client.new)
      @egress = egress
    end

    # POST a JSON body to a provider endpoint through validated egress.
    # @return [Egress::Client::Response] whatever the one door returns.
    # @raise [Egress::UrlPolicy::Refused] before any connection, when the URL is disallowed.
    def post_json(url, payload, headers: {})
      @egress.post(
        url,
        body: JSON.generate(payload),
        headers: { "content-type" => "application/json" }.merge(headers)
      )
    end

    # GET through validated egress.
    def get(url, headers: {})
      @egress.get(url, headers: headers)
    end
  end
end
