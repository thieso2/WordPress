# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"

# Assistance abilities pipeline vs the oracle's WP_Abilities_Registry / WP_Ability
# (wp-includes/abilities-api/*). The bridge registers a fixed battery of abilities on the oracle
# and reports the observable contract; here the SAME abilities are built in an
# Assistance::Registry and the two are compared fact for fact.
#
# What is being proven is ORDER, not just outcome (BR-MIGRATE-273 / -275): each case carries the
# sequence in which the permission and execute callbacks ran, so a malformed input that leaves
# the log EMPTY is the observable form of "input is validated before authorization".
module AbilitiesOracle
  BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"
  BRIDGE = File.expand_path("support/abilities_oracle.php", __dir__)

  module_function

  def available?
    File.exist?(BOOTSTRAP) && system("sh", "-c", "command -v php > /dev/null 2>&1")
  end

  def payload
    @payload ||= begin
      stdout, stderr, status = Open3.capture3({ "WP_ORACLE_BOOTSTRAP" => BOOTSTRAP }, "php", BRIDGE)
      raise "oracle bridge failed: #{stderr}" unless status.success?

      JSON.parse(stdout)
    end
  end
end

RSpec.describe Assistance::Registry do
  before { skip "PHP oracle not available" unless AbilitiesOracle.available? }

  let(:payload) { AbilitiesOracle.payload }

  # An order log shared by the callbacks, reset per execution — the rebuild's mirror of the
  # oracle bridge's $GLOBALS['ability_order'].
  let(:order) { [] }

  # A registry built exactly as the bridge builds the oracle's, minus the hook plumbing.
  let(:registry) do
    reg = described_class.new
    reg.register_category("demo", label: "Demo", description: "Demo category")

    reg.register("demo/echo", label: "Echo", description: "Echoes n", category: "demo",
      input_schema: { type: "object", properties: { n: { type: "integer" } }, required: ["n"] },
      output_schema: { type: "object", properties: { n: { type: "integer" } } },
      permission_callback: ->(_i) { order << "perm"; true },
      execute_callback: ->(i) { order << "exec"; { "n" => i["n"] } })

    reg.register("demo/deny", label: "Deny", description: "Denied", category: "demo",
      input_schema: { type: "object", properties: { n: { type: "integer" } } },
      permission_callback: ->(_i) { order << "perm"; false },
      execute_callback: ->(i) { order << "exec"; i })

    reg.register("demo/badout", label: "BadOut", description: "Bad output", category: "demo",
      output_schema: { type: "integer" },
      permission_callback: -> { order << "perm"; true },
      execute_callback: -> { order << "exec"; "a string" })

    reg.register("demo/noschema", label: "NoSchema", description: "No schema", category: "demo",
      permission_callback: -> { order << "perm"; true },
      execute_callback: -> { order << "exec"; "ok" })

    reg.register("demo/pub", label: "Pub", description: "Public", category: "demo",
      meta: { public: true },
      permission_callback: -> { true }, execute_callback: -> { true })
    reg
  end

  def run_case(name, input, has_input)
    order.clear
    result = has_input ? registry.get(name).execute(input) : registry.get(name).execute
    {
      "code"  => result.error? ? result.code : nil,
      "value" => result.error? ? nil : result.value,
      "order" => order.dup
    }
  end

  it "matches the oracle's public/show_in_rest defaults (BR-MIGRATE-272)" do
    echo = registry.get("demo/echo")
    pub  = registry.get("demo/pub")
    got = {
      "echo_public" => echo.public?, "echo_show_in_rest" => echo.show_in_rest?,
      "pub_public" => pub.public?, "pub_show_in_rest" => pub.show_in_rest?
    }
    expect(got).to eq(payload["defaults"])
    # The literal rule, stated: an ability is neither public nor in REST by default.
    expect(echo.public?).to be(false)
    expect(echo.show_in_rest?).to be(false)
  end

  it "matches the oracle's registration outcomes (BR-MIGRATE-269/270/271)" do
    outcomes = {
      # BR-270: re-registering an existing ability fails and returns nil (no overwrite).
      "duplicate_is_null" => registry.register("demo/echo", label: "x", description: "y", category: "demo",
        permission_callback: -> { true }, execute_callback: -> { true }).nil?,
      # BR-269: namespace prefix mandatory; a bare name is rejected.
      "bad_name_is_null" => registry.register("noNamespace", label: "x", description: "y", category: "demo",
        permission_callback: -> { true }, execute_callback: -> { true }).nil?,
      # BR-271: the category must already be registered.
      "no_category_is_null" => registry.register("demo/orphan", label: "x", description: "y", category: "missing",
        permission_callback: -> { true }, execute_callback: -> { true }).nil?,
      # BR-269: names are lowercase only.
      "uppercase_is_null" => registry.register("demo/Echo-Upper", label: "x", description: "y", category: "demo",
        permission_callback: -> { true }, execute_callback: -> { true }).nil?
    }
    expect(outcomes).to eq(payload["registration"])
  end

  it "reproduces every execute() case — code, value AND callback order — exactly (BR-MIGRATE-273/274/275)" do
    got = {
      "valid"          => run_case("demo/echo", { "n" => 5 }, true),
      "malformed"      => run_case("demo/echo", { "n" => "not-an-int" }, true),
      "denied"         => run_case("demo/deny", { "n" => 1 }, true),
      "bad_output"     => run_case("demo/badout", nil, false),
      "missing_schema" => run_case("demo/noschema", { "x" => 1 }, true),
      "noschema_null"  => run_case("demo/noschema", nil, false)
    }
    divergences = payload["cases"].filter_map do |name, expected|
      next if got[name] == expected

      "#{name}\n    oracle:  #{expected.to_json}\n    rebuild: #{got[name].to_json}"
    end
    expect(divergences).to be_empty, "pipeline diverges from the oracle:\n\n#{divergences.join("\n")}"
  end

  it "rejects a malformed request before authorization runs (BR-MIGRATE-275, stated directly)" do
    # The order log is the evidence: the permission callback must not appear.
    result = run_case("demo/echo", { "n" => "not-an-int" }, true)
    expect(result["code"]).to eq("ability_invalid_input")
    expect(result["order"]).to eq([]) # neither perm nor exec ran
  end

  it "runs the pipeline stages in exactly the documented order for a happy path" do
    result = run_case("demo/echo", { "n" => 5 }, true)
    expect(result["order"]).to eq(%w[perm exec]) # permission (post-validation) then execute
    expect(result["value"]).to eq("n" => 5)
  end
end
