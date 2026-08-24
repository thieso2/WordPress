# frozen_string_literal: true

module Tenancy
  # Host+path → Site. This is the OBSERVABLE core of what the legacy did across
  # ms-settings.php (network + site lookup from the request) and sunrise.php (BR-MS-06 /
  # BR-MIGRATE-361, the domain-mapping drop-in that ran before network resolution).
  #
  # ⚠️ sunrise.php was a DROP-IN — a hook/extension mechanism, gone under AD-01/DEV-011. So
  # is the network-activated-plugins load order (BR-MS-07 / BR-MIGRATE-362, "plugins load
  # before muplugins_loaded"): both are LOAD-ORDER extension points, not behaviour, and
  # there is no plugin system to order. The one behaviour they existed to produce — map an
  # incoming host (and, for subdirectory installs, a leading path segment) to a site — is
  # reproduced here as a plain lookup. Anything beyond an exact host/path match (wildcard
  # domain mapping, per-domain aliases) is NOTED as a deferred capability, not built.
  module Resolver
    module_function

    # Resolve a request host and path to a Site, or nil. nil is not an error: with multisite
    # disabled there are no sites and this always returns nil, which keeps the surface on the
    # single-site path. Never raises on a miss.
    def resolve(host:, path: "/")
      return nil unless Tenancy.enabled?
      return nil if host.blank?

      host = normalize_host(host)

      # Subdirectory install: a leading path segment can select the site (path-based).
      # Try the most specific (host + first path segment) before the host-only match.
      segment = path.to_s.split("/").reject(&:empty?).first
      if segment
        by_path = Tenancy::Site.find_by(domain: host, path: "/#{segment}/")
        return by_path if by_path
      end

      Tenancy::Site.find_by(domain: host, path: "/")
    end

    # Strip a port and a leading `www.`, lowercase — the normalization get_blog_details()
    # applied before matching. Not a full public-suffix parse; a deployment that needs
    # wildcard subdomains adds that here (noted).
    def normalize_host(host)
      host.to_s.downcase.split(":").first.to_s.sub(/\Awww\./, "")
    end
  end
end
