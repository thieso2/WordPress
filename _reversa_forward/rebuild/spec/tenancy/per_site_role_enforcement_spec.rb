# frozen_string_literal: true

require "rails_helper"
require_relative "tenancy_helper"

# BR-MS-04 per-site role ENFORCEMENT. The assignment half (User#assign_role(site_id:))
# and the enforcement half (Access::BasePolicy#actor_roles consulting Tenancy.current_site)
# must agree: on a single site the per-site path is inert (byte-identical to Waves 0-4);
# under multisite a role scoped to site A grants capabilities only while site A is served.
RSpec.describe "Per-site role enforcement (BR-MS-04)", :tenancy do
  # A minimal policy exercising the shared capability plumbing.
  let(:policy_class) do
    Class.new(Access::BasePolicy) do
      def can_edit_posts? = actor_holds?("edit_posts")
    end
  end

  def policy_for(user) = policy_class.new(user, nil)

  describe "single site (multisite OFF — the acceptance gate)" do
    it "reads nil-scoped roles exactly as before" do
      user = Identity::User.create!(login: "ss_admin", email: "ss@example.test", nicename: "ss-admin", password: "pw")
      user.assign_role("administrator") # site_id: nil

      expect(Tenancy.current_site).to be_nil
      expect(policy_for(user).can_edit_posts?).to be(true)
    end

    it "does not grant capabilities from a site-scoped role when tenancy is off" do
      user = Identity::User.create!(login: "ss_scoped", email: "ss2@example.test", nicename: "ss-scoped", password: "pw")
      # A stray site-scoped assignment must not leak into single-site evaluation.
      user.assign_role("administrator", site_id: 999)

      expect(policy_for(user).can_edit_posts?).to be(false)
    end
  end

  describe "multisite ON" do
    it "grants a site-scoped role only while that site is the current tenant" do
      with_multisite do
        site_a = Tenancy::Site.create!(domain: "a.example", path: "/", name: "A", schema_name: "site_a")
        site_b = Tenancy::Site.create!(domain: "b.example", path: "/", name: "B", schema_name: "site_b")
        user = Identity::User.create!(login: "ms_user", email: "ms@example.test", nicename: "ms-user", password: "pw")
        user.assign_role("administrator", site_id: site_a.id)

        Tenancy::Current.site = site_a
        expect(policy_for(user).can_edit_posts?).to be(true), "admin on site A while serving A"

        Tenancy::Current.site = site_b
        expect(policy_for(user).can_edit_posts?).to be(false), "no role on site B"
      end
    end
  end
end
