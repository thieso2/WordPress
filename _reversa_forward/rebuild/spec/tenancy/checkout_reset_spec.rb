# frozen_string_literal: true

require "rails_helper"
require_relative "tenancy_helper"

# (d) checkout RESETS search_path — RISK-009.
# A returned connection may carry the previous borrower's tenant. The pool must not hand
# that leak to the next borrower, so search_path is reset on CHECKOUT (never on checkin):
# `checkout_and_verify` calls `connection.clean!`, which runs the :checkout callbacks
# (config/initializers/tenancy.rb). We drive `clean!` directly — it IS the checkout hook —
# and assert the leaked value is overwritten from Tenancy::Current, not preserved.
RSpec.describe "search_path reset on connection checkout", :tenancy do
  let(:conn) { ActiveRecord::Base.connection }

  it "overwrites a leaked tenant search_path with the borrower's current context" do
    with_multisite do
      site = provision_site(domain: "checkout.example", schema_name: "co_site")

      # Simulate a previous borrower that left tenant `co_site` on the connection...
      conn.execute(%(SET search_path TO "co_site", "public"))
      expect(current_search_path).to include("co_site")

      # ...then the next borrower's context is NO tenant (a global/single-site request).
      Tenancy::Current.site = nil
      conn.clean! # exactly what ConnectionPool#checkout_and_verify calls on checkout.

      # The leak is gone: reset to the global schema, not left pointing at co_site's data.
      expect(current_search_path).not_to include("co_site")
      expect(current_search_path).to include("public")

      # And a borrower whose context IS a tenant gets that tenant, freshly, on checkout.
      Tenancy::Current.site = site
      conn.execute(%(SET search_path TO "public")) # pretend a prior borrower left globals
      conn.clean!
      expect(current_search_path).to include("co_site")
    end
  end

  it "is a NO-OP when multisite is disabled (single-site parity untouched)" do
    # Default state: disabled. A checkout must not issue any SET, so whatever the search_path
    # was, clean! leaves it exactly as-is.
    conn.execute(%(SET search_path TO "public"))
    before = current_search_path
    conn.clean!
    expect(current_search_path).to eq(before)
  ensure
    conn.execute(%(SET search_path TO "$user", public))
  end
end
