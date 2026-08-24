# frozen_string_literal: true

require "rails_helper"

# BR-MIGRATE-274: JSON Schema validation of input and output. The reproduction covers the subset
# the abilities pipeline exercises; these are the direct unit assertions behind the differential
# suite.
RSpec.describe Assistance::SchemaValidator do
  it "passes a conforming value and returns nil" do
    schema = { type: "object", properties: { n: { type: "integer" } }, required: ["n"] }
    expect(described_class.validate({ "n" => 5 }, schema)).to be_nil
  end

  it "rejects a wrong-typed property" do
    schema = { type: "object", properties: { n: { type: "integer" } } }
    expect(described_class.validate({ "n" => "x" }, schema)).to match(/not of type integer/)
  end

  it "rejects a missing required property" do
    schema = { type: "object", properties: { n: { type: "integer" } }, required: ["n"] }
    expect(described_class.validate({}, schema)).to match(/missing required property n/)
  end

  it "enforces enum membership" do
    schema = { type: "string", enum: %w[a b] }
    expect(described_class.validate("c", schema)).to match(/not one of/)
    expect(described_class.validate("a", schema)).to be_nil
  end

  it "enforces numeric bounds" do
    schema = { type: "integer", minimum: 1, maximum: 10 }
    expect(described_class.validate(0, schema)).to match(/greater than or equal to 1/)
    expect(described_class.validate(11, schema)).to match(/less than or equal to 10/)
    expect(described_class.validate(5, schema)).to be_nil
  end

  it "validates array items" do
    schema = { type: "array", items: { type: "integer" } }
    expect(described_class.validate([1, "x"], schema)).to match(/\[1\] is not of type integer/)
    expect(described_class.validate([1, 2], schema)).to be_nil
  end

  it "treats an empty or nil schema as always valid" do
    expect(described_class.validate("anything", {})).to be_nil
    expect(described_class.validate("anything", nil)).to be_nil
  end

  it "accepts symbol- or string-keyed schemas and payloads alike" do
    schema = { "type" => "object", "properties" => { "n" => { "type" => "integer" } }, "required" => ["n"] }
    expect(described_class.validate({ n: 5 }, schema)).to be_nil
  end
end

# BR-MIGRATE-276: __wakeup/__sleep were PHP unserialization guards on the registry and abilities,
# because those objects hold callables. This is ABSORBED, not reproduced: Ruby's Marshal is never
# used on abilities, and because an Ability holds Procs, Marshal.dump raises on its own — there is
# nothing to guard against and no bespoke guard to add.
RSpec.describe "Assistance::Ability serialization (BR-MIGRATE-276 absorbed)" do
  it "cannot be Marshal-dumped because it holds callables — the guard is unnecessary" do
    registry = Assistance::Registry.new
    registry.register_category("demo", label: "D", description: "d")
    ability = registry.register("demo/x", label: "X", description: "x", category: "demo",
      permission_callback: -> { true }, execute_callback: -> { true })
    expect { Marshal.dump(ability) }.to raise_error(TypeError)
  end
end
