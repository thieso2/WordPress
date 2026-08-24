# frozen_string_literal: true

require "rails_helper"
require_relative "tenancy_helper"

# (b) creating a second tenant gives it an ISOLATED schema.
# The acceptance proof that schema-per-site (BR-MS-01) actually isolates data: two tenants,
# two schemas, a write to one invisible to the other, and both invisible to the global
# schema. EXPECT-HEAVY, as this track must be.
RSpec.describe "Tenancy schema isolation", :tenancy do
  it "gives each site its own schema and keeps blog-scoped rows from leaking across tenants" do
    with_multisite do
      site_a = provision_site(domain: "alpha.example", schema_name: "site_alpha")
      site_b = provision_site(domain: "beta.example",  schema_name: "site_beta")

      expect(site_a.provisioned?).to be(true)
      expect(site_b.provisioned?).to be(true)
      expect(site_a.schema_name).not_to eq(site_b.schema_name)

      # A write inside tenant A lands in tenant A's schema only.
      Tenancy.switch(site_a) { insert_setting("only_in_alpha") }

      alpha_names = Tenancy.switch(site_a) do
        ActiveRecord::Base.connection.select_values("SELECT name FROM settings")
      end
      beta_names = Tenancy.switch(site_b) do
        ActiveRecord::Base.connection.select_values("SELECT name FROM settings")
      end

      expect(alpha_names).to include("only_in_alpha")
      expect(beta_names).not_to include("only_in_alpha")
    end
  end

  it "resolves the model layer (not just raw SQL) to the active tenant's schema" do
    with_multisite do
      site_a = provision_site(domain: "one.example", schema_name: "site_one")
      site_b = provision_site(domain: "two.example", schema_name: "site_two")

      # Configuration::Setting is a blog-scoped model; the same class writes to different
      # physical tables depending only on the active search_path — no discriminator column.
      Tenancy.switch(site_a) { Configuration::Setting.create!(name: "tenant_marker", value: "A") }

      in_a = Tenancy.switch(site_a) { Configuration::Setting.find_by(name: "tenant_marker")&.value }
      in_b = Tenancy.switch(site_b) { Configuration::Setting.find_by(name: "tenant_marker")&.value }

      expect(in_a).to eq("A")
      expect(in_b).to be_nil
    end
  end

  it "gives each tenant an INDEPENDENT identity sequence (LIKE INCLUDING ALL)" do
    with_multisite do
      site_a = provision_site(domain: "seq-a.example", schema_name: "seq_a")
      site_b = provision_site(domain: "seq-b.example", schema_name: "seq_b")

      id_a = Tenancy.switch(site_a) do
        Configuration::Setting.create!(name: "first", value: "1").id
      end
      id_b = Tenancy.switch(site_b) do
        Configuration::Setting.create!(name: "first", value: "1").id
      end

      # Both start their own sequence at 1 rather than sharing public's counter.
      expect(id_a).to eq(id_b)
    end
  end

  it "keeps GLOBAL tables shared: a user created under one tenant is visible under another" do
    with_multisite do
      site_a = provision_site(domain: "g-a.example", schema_name: "glob_a")
      site_b = provision_site(domain: "g-b.example", schema_name: "glob_b")

      user = Tenancy.switch(site_a) do
        Identity::User.create!(login: "netizen", email: "n@example.com", nicename: "netizen",
                               display_name: "Netizen", password: "correct horse battery")
      end

      seen_from_b = Tenancy.switch(site_b) { Identity::User.find_by(login: "netizen") }
      expect(seen_from_b).to be_present
      expect(seen_from_b.id).to eq(user.id)
    end
  end
end
