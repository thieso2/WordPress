# frozen_string_literal: true

require "rails_helper"
require_relative "capability_matrix_differential_spec"

# BR-MIGRATE-109 (BR-CAP-13) / BR-MIGRATE-110 (BR-CAP-15) / T-03 / BR-CAP-14.
RSpec.describe Access::RoleCatalogue do
  describe "against the oracle's populate_roles() output" do
    before { skip "PHP oracle not available" unless CapabilitiesOracle.available? }

    it "holds exactly the capabilities each built-in role holds, minus the level_N shims" do
      oracle_roles = CapabilitiesOracle.payload.fetch("roles")
      oracle_roles.each do |role, capabilities|
        expect(described_class.capabilities_for([role]).sort).to eq(capabilities.sort),
                                                                  "role #{role} diverges from the oracle"
      end
    end
  end

  # T-03: "A role name not in the known role set -> LOAD IT ANYWAY and report it. An
  # unknown role is data, not corruption." It loads; it grants nothing.
  it "lets an unknown role load and grants it nothing" do
    user = Identity::User.create!(login: "exotic", email: "exotic@example.com", nicename: "exotic",
                                  password: "pw")
    user.assign_role("superhero")
    expect(user.reload.roles).to eq(["superhero"])
    expect(described_class.known?("superhero")).to be(false)
    expect(described_class.capabilities_for(user.roles)).to eq([])
    expect(Access::SitePolicy.new(user, nil).permit?(:read)).to be(false)
    # BR-CAP-04 still applies: even an unknown role exists.
    expect(Access::SitePolicy.new(user, nil).permit?(:exist)).to be(true)
  end

  # BR-CAP-14, DISCARDED: no configuration may outrank the stored roles.
  it "cannot be outranked by a super_admins setting" do
    user = Identity::User.create!(login: "wannabe", email: "wannabe@example.com", nicename: "wannabe",
                                  password: "pw")
    user.assign_role("subscriber")
    Configuration::Setting.set("super_admins", [user.login])
    expect(Access::SettingPolicy.new(user, nil).permit?(:edit)).to be(false)
    expect(Access::UserPolicy.new(user, user).permit?(:remove)).to be(false)
  end
end
