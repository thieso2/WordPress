# frozen_string_literal: true

require "rails_helper"
require_relative "tenancy_helper"

# The signup → activate flow at the model level (wp-signup.php / wp-activate.php). Activation
# provisions the new schema + assigns the first member the site's administrator role
# (BR-MS-04: roles are per-site).
RSpec.describe "Tenancy signup and activation", :tenancy do
  it "writes a pending Signup with an activation key" do
    signup = Tenancy::Signup.create!(kind: "blog", user_login: "wanda", user_email: "wanda@example.com",
                                     domain: "wanda.example", path: "/", title: "Wanda's Blog")
    expect(signup.activation_key).to be_present
    expect(signup).not_to be_activated
    expect(Tenancy::Signup.pending).to include(signup)
  end

  it "activates a blog signup: creates the user, provisions the schema, assigns admin per-site" do
    with_multisite do
      signup = Tenancy::Signup.create!(kind: "blog", user_login: "greg", user_email: "greg@example.com",
                                       domain: "greg.example", path: "/", title: "Greg's Site")

      result = signup.activate!

      expect(result.user).to be_present
      expect(result.password).to be_present
      expect(result.site).to be_present
      expect(result.site.provisioned?).to be(true)
      expect(signup.reload).to be_activated

      # BR-MS-04: the role is scoped to the NEW site, not global.
      expect(result.user.roles(site_id: result.site.id)).to include("administrator")
      expect(result.user.roles(site_id: nil)).not_to include("administrator")
    end
  end

  it "activates a user-only signup: creates the user, no site" do
    with_multisite do
      signup = Tenancy::Signup.create!(kind: "user", user_login: "solo", user_email: "solo@example.com")
      result = signup.activate!
      expect(result.user.login).to eq("solo")
      expect(result.site).to be_nil
    end
  end

  it "is idempotent: activating an already-active key does not double-provision" do
    with_multisite do
      signup = Tenancy::Signup.create!(kind: "blog", user_login: "twice", user_email: "twice@example.com",
                                       domain: "twice.example", path: "/", title: "Twice")
      first = signup.activate!
      expect { signup.activate! }.not_to change(Tenancy::Site, :count)
      second = signup.activate!
      expect(second.site.id).to eq(first.site.id)
    end
  end

  it "reuses an existing global user rather than creating a duplicate" do
    with_multisite do
      existing = Tenancy.without_tenant do
        Identity::User.create!(login: "already", email: "already@example.com", nicename: "already",
                               display_name: "Already", password: "correct horse battery staple")
      end
      signup = Tenancy::Signup.create!(kind: "blog", user_login: "already", user_email: "already@example.com",
                                       domain: "already.example", path: "/", title: "Already")
      result = signup.activate!
      expect(result.user.id).to eq(existing.id)
    end
  end
end

RSpec.describe "Tenancy::Resolver", :tenancy do
  it "returns nil when multisite is disabled" do
    expect(Tenancy::Resolver.resolve(host: "anything.example")).to be_nil
  end

  it "resolves a host to its site under multisite, normalizing www and port" do
    with_multisite do
      site = provision_site(domain: "mapped.example", schema_name: "mapped_site")
      expect(Tenancy::Resolver.resolve(host: "www.mapped.example:3000")).to eq(site)
      expect(Tenancy::Resolver.resolve(host: "unknown.example")).to be_nil
    end
  end
end
