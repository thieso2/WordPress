# frozen_string_literal: true

require "rails_helper"
require_relative "tenancy_helper"

# (a) single-site parity unbroken — the ACCEPTANCE GATE, at the unit level.
# With multisite off (the default), every tenancy entry point must be a transparent no-op:
# no SET search_path, no super admins, no behaviour change to Access. The 25-screen parity
# run is the system-level proof; these are the fast invariants behind it.
RSpec.describe "Tenancy is a transparent no-op single-site", :tenancy do
  it "defaults to disabled" do
    expect(Tenancy.enabled?).to be(false)
  end

  it "never issues a SET search_path when disabled" do
    conn = ActiveRecord::Base.connection
    conn.execute(%(SET search_path TO "$user", public))
    before = conn.select_value("SHOW search_path")

    # apply / checkout-reset are both guarded on enabled?
    Tenancy.apply_search_path!
    Tenancy.reset_search_path_on_checkout!(conn)
    conn.clean!

    expect(conn.select_value("SHOW search_path")).to eq(before)
  ensure
    ActiveRecord::Base.connection.execute(%(SET search_path TO "$user", public))
  end

  it "reports no super admins when disabled, whatever the network option says" do
    # Even if a site_admins list were present, disabled multisite means no network exists.
    Tenancy::NetworkSetting["site_admins"] = [1]
    user = Identity::User.new(id: 1)
    expect(Tenancy.super_admin?(user)).to be(false)
  end

  it "raises rather than silently switching when disabled" do
    expect { Tenancy.switch(nil) { :noop } }.to raise_error(Tenancy::NotEnabled)
  end

  it "current_site is nil off the tenant path" do
    expect(Tenancy.current_site).to be_nil
    expect(Tenancy.current_schema).to be_nil
  end
end

# BR-MS-05 (BR-MIGRATE-360): super admins bypass every check except do_not_allow — and this
# wiring must NOT change single-site Access evaluation.
RSpec.describe "Access super-admin bypass (BR-MS-05)", :tenancy do
  # A plain user holding no capabilities.
  let(:nobody) do
    Identity::User.create!(login: "nobody", email: "nobody@example.com", nicename: "nobody",
                           display_name: "Nobody", password: "correct horse battery staple")
  end

  it "does NOT bypass single-site: an unprivileged actor is still refused (parity preserved)" do
    # Disabled: base_policy reaches the ordinary role check.
    policy = Access::SitePolicy.new(nobody, nil)
    expect(policy.permit?(:manage_options)).to be(false)
  end

  it "bypasses every capability under multisite when the actor is a network super admin" do
    with_multisite do
      Tenancy::NetworkSetting["site_admins"] = [nobody.id]
      policy = Access::SitePolicy.new(nobody, nil)
      # A capability nobody holds — allowed purely by super-admin standing.
      expect(policy.permit?(:manage_options)).to be(true)
      expect(policy.permit?(:switch_themes)).to be(true)
    end
  end

  it "still cannot satisfy do_not_allow, even as a super admin (BR-CAP-02)" do
    with_multisite do
      Tenancy::NetworkSetting["site_admins"] = [nobody.id]
      # delete_site maps to DO_NOT_ALLOW on a single site (site_policy.rb:45); a super admin
      # is refused it, because do_not_allow is the one primitive the bypass excludes.
      policy = Access::SitePolicy.new(nobody, nil)
      expect(policy.permit?(:delete_site)).to be(false)
    end
  end

  it "does not elevate a non-member under multisite" do
    with_multisite do
      Tenancy::NetworkSetting["site_admins"] = [] # nobody is a super admin
      policy = Access::SitePolicy.new(nobody, nil)
      expect(policy.permit?(:manage_options)).to be(false)
    end
  end
end
