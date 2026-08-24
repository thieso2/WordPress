# frozen_string_literal: true

require "rails_helper"

# BR-MIGRATE-278: abilities exposed to AI models as callable functions, via an explicit allow-list
# (WP_AI_Client_Ability_Function_Resolver). No ambient registry — the resolver holds the one it
# was given.
RSpec.describe Assistance::FunctionResolver do
  let(:registry) do
    reg = Assistance::Registry.new
    reg.register_category("tec", label: "Events", description: "Event abilities")
    reg.register("tec/create-event", label: "Create", description: "Creates an event", category: "tec",
      input_schema: { type: "object", properties: { title: { type: "string" } }, required: ["title"] },
      permission_callback: ->(_i) { true },
      execute_callback: ->(i) { { "id" => 1, "title" => i["title"] } })
    reg.register("tec/secret", label: "Secret", description: "Not exposed", category: "tec",
      permission_callback: -> { true }, execute_callback: -> { "secret" })
    reg
  end

  it "encodes ability names to function names and back (resolver.php:213/227)" do
    expect(described_class.ability_name_to_function_name("tec/create-event")).to eq("wpab__tec__create-event")
    expect(described_class.function_name_to_ability_name("wpab__tec__create-event")).to eq("tec/create-event")
  end

  it "recognises ability function calls by prefix" do
    resolver = described_class.new(registry, allowed: [])
    expect(resolver.ability_call?("wpab__tec__create-event")).to be(true)
    expect(resolver.ability_call?("some_other_tool")).to be(false)
  end

  it "runs an allowed ability through its full pipeline" do
    resolver = described_class.new(registry, allowed: ["tec/create-event"])
    result = resolver.execute("wpab__tec__create-event", { "title" => "Launch" })
    expect(result).to be_ok
    expect(result.value).to eq("id" => 1, "title" => "Launch")
  end

  it "refuses an ability that is not on the allow-list, even when it is registered" do
    resolver = described_class.new(registry, allowed: ["tec/create-event"])
    result = resolver.execute("wpab__tec__secret")
    expect(result).to be_error
    expect(result.code).to eq("ability_not_allowed")
  end

  it "reports ability_not_found when the allowed name is not registered" do
    resolver = described_class.new(registry, allowed: ["tec/ghost"])
    result = resolver.execute("wpab__tec__ghost")
    expect(result.code).to eq("ability_not_found")
  end

  it "reports invalid_ability_call for a non-ability function name" do
    resolver = described_class.new(registry, allowed: [])
    expect(resolver.execute("plain_tool").code).to eq("invalid_ability_call")
  end

  it "accepts Ability objects (not just names) in the allow-list" do
    ability = registry.get("tec/create-event")
    resolver = described_class.new(registry, allowed: [ability])
    expect(resolver.execute("wpab__tec__create-event", { "title" => "X" })).to be_ok
  end
end
