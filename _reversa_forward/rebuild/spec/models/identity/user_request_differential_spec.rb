# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"

# Identity::UserRequest against the oracle's wp_create_user_request() (user.php:4803).
module UserRequestOracle
  BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"
  BRIDGE = File.expand_path("support/user_request_oracle.php", __dir__)

  # [email, action, status, precreate]
  CASES = [
    ["", "export_personal_data", "pending"],
    ["not-an-email", "export_personal_data", "pending"],
    ["someone@example.com", "bogus_action", "pending"],
    ["someone@example.com", "export_personal_data", "completed"],
    ["someone@example.com", "export_personal_data", "pending"],
    ["someone@example.com", "remove_personal_data", "confirmed"],
    ["oracle_editor@example.com", "remove_personal_data", "pending"],
    ["Someone@Example.com", "Export_Personal_Data", "pending"],
    ["someone@example.com", "export_personal_data", "pending", ["someone@example.com", "export_personal_data"]],
    ["someone@example.com", "remove_personal_data", "pending", ["someone@example.com", "export_personal_data"]]
  ].freeze

  module_function

  def available?
    File.exist?(BOOTSTRAP) && system("sh", "-c", "command -v php > /dev/null 2>&1")
  end

  def payload
    @payload ||= begin
      stdout, stderr, status = Open3.capture3({ "WP_ORACLE_BOOTSTRAP" => BOOTSTRAP }, "php", BRIDGE,
                                              stdin_data: JSON.generate(CASES))
      raise "oracle bridge failed: #{stderr}" unless status.success?

      JSON.parse(stdout)
    end
  end
end

RSpec.describe Identity::UserRequest do
  before { skip "PHP oracle not available" unless UserRequestOracle.available? }

  # The oracle attributes a request to the user holding the email (post_author); the
  # comparison below maps that onto `user_id` through the one user it needs.
  let!(:editor) do
    Identity::User.create!(login: "oracle_editor", email: "oracle_editor@example.com",
                           nicename: "oracle_editor", password: "pw")
  end

  it "answers every case as the oracle does" do
    divergences = UserRequestOracle::CASES.zip(UserRequestOracle.payload["results"]).filter_map do |c, expected|
      email, action, status, precreate = c
      Identity::DataRequest.delete_all
      described_class.call(email: precreate[0], action: precreate[1]) if precreate
      outcome = described_class.call(email: email, action: action, status: status)

      got = if outcome.success?
              r = outcome.request
              { "request" => { "email" => r.email, "action" => described_class::ACTIONS.key(r.kind),
                               "status" => "request-#{r.status}", "author" => r.user_id.to_i.positive? ? 1 : 0 } }
            else
              e = outcome.errors.first
              { "error" => { "code" => e.code, "message" => e.message } }
            end
      # post_author is an id in the oracle; only "attributed or not" is comparable.
      expected = expected.deep_dup
      expected["request"]["author"] = expected["request"]["author"].positive? ? 1 : 0 if expected["request"]
      next if got == expected

      "#{c.inspect}\n    oracle:  #{expected.to_json}\n    rebuild: #{got.to_json}"
    end

    expect(divergences).to be_empty, "user requests diverge from the oracle:\n\n#{divergences.join("\n")}"
  end

  it "is reachable as the AGG-User commands" do
    expect(editor.request_data_export).to be_success
    expect(editor.request_erasure).to be_success
    expect(editor.request_data_export.errors.map(&:code)).to eq(["duplicate_request"])
    expect(editor.data_requests.pluck(:kind).sort).to eq(%w[erasure export])
  end
end
