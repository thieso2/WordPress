# frozen_string_literal: true

require "net/http"
require "uri"

module Parity
  # The one-way client to the reference WordPress 7.2-alpha-63330 instance.
  #
  # AD-08: "the parity oracle is architecture, not tooling." This is a first-class
  # component of the system, built in Wave 0 and retired only after Wave 5.
  #
  # ⚠️ RISK-001 is the project's single point of failure and this client plus the seeded
  # corpus is its entire mitigation. If the oracle is not reachable the harness must FAIL
  # LOUDLY, never skip: a silently-skipped parity suite reports green while proving
  # nothing, which is the exact failure mode AD-08 exists to prevent.
  class OracleClient
    class Unreachable < StandardError; end

    Response = Struct.new(:status, :body, :content_type, :path, :location, keyword_init: true)

    def initialize(base_url: ENV.fetch("ORACLE_URL", "http://127.0.0.1:8099"))
      @base = URI.parse(base_url)
    end

    def available?
      get("/")
      true
    rescue Unreachable
      false
    end

    def get(path)
      uri = URI.join(@base, path)
      response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 30) do |http|
        http.get(uri.request_uri, "User-Agent" => "reversa-parity-harness/1.0")
      end
      Response.new(status: response.code.to_i, body: response.body.to_s,
                   content_type: response["content-type"].to_s, path: path,
                   location: response["location"])
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, SocketError => e
      raise Unreachable, <<~MSG
        The parity oracle is not reachable at #{@base}.

        RISK-001: with no live deployment, the reference WordPress instance is the ONLY
        executable definition of the 363 rules. The harness fails rather than skips.

        Start it with:  bin/oracle up
      MSG
    end
  end
end
