# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"

# Identity::Registration against the oracle's register_new_user() (wp-includes/user.php
# :3548) -- every error code, every LITERAL string, and the user a successful
# registration produces (login, nicename, display name, email, default role).
#
# The oracle runs each case inside a rolled-back transaction, so the success cases are
# real writes through wp_insert_user() that never reach the corpus (RISK-002).
module RegistrationOracle
  BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"
  BRIDGE = File.expand_path("support/registration_oracle.php", __dir__)

  # [login, email]. Deliberately uneven: each row reaches one arm of the elseif chains.
  CASES = [
    ["", ""],
    ["   ", "x"],
    ["bad<b>name", "a@b.co"],
    ["<script>alert(1)</script>", "s@b.co"],
    ["ok name", "a@b.co"],
    ["oracle_admin", "new@example.com"],
    ["Oracle_Admin", "new@example.com"],
    ["newbie", ""],
    ["newbie", "notanemail"],
    ["newbie", "a@b"],
    ["newbie", "a@b..co"],
    ["newbie", "a@-b.co"],
    ["newbie", "a b@b.co"],
    ["newbie", "oracle@example.com"],
    ["newbie", "ORACLE@example.com"],
    ["a" * 61, "long@example.com"],
    ["a" * 60, "sixty@example.com"],
    ["@@@", "at@example.com"],
    ["0", "zero@example.com"],
    ["oracle_editor2", "fresh@example.com"],
    ["José Ñandú", "jose@example.com"],
    ["with%20pct", "p@example.com"],
    ["a&amp;b", "amp@example.com"],
    ["tab\tname", "t@example.com"],
    ["dots.and-dashes_ok", "d@example.com"],
    ["oracle-editor", "nicename-collision@example.com"],
    ["bad<b>name", "oracle@example.com"]
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

RSpec.describe Identity::Registration do
  before { skip "PHP oracle not available" unless RegistrationOracle.available? }

  let(:payload) { RegistrationOracle.payload }
  let(:login_url) { payload.dig("fixtures", "login_url") }

  # The same six users the oracle has, so username_exists / email_exists / the nicename
  # suffix see the same neighbours; the same settings the messages interpolate.
  before do
    %w[role_assignments users settings].each { |t| ActiveRecord::Base.connection.execute("DELETE FROM #{t}") }
    payload.dig("fixtures", "users").each do |row|
      u = Identity::User.new(login: row["login"], nicename: row["nicename"], email: row["email"],
                             display_name: row["display_name"])
      u.password_digest = "$2a$12$#{"x" * 53}"
      u.save!(validate: false)
    end
    payload.dig("fixtures", "settings").each { |k, v| Configuration::Setting.set(k, v) }
    # users_can_register is '0' in the corpus; the register_new_user() function the
    # bridge calls sits BELOW that gate, so the gate is opened here and tested alone.
    Configuration::Setting.set("users_can_register", "1")
  end

  def run(login, email)
    described_class.call(login: login, email: email, login_url: login_url)
  end

  it "produces the oracle's error codes and LITERAL messages, in the oracle's order, for every case" do
    divergences = RegistrationOracle::CASES.zip(payload["results"]).filter_map do |(login, email), expected|
      registration = run(login, email)
      got = if registration.success?
              { "user" => { "login" => registration.user.login, "nicename" => registration.user.nicename,
                            "email" => registration.user.email, "display_name" => registration.user.display_name,
                            "roles" => registration.user.roles } }
            else
              { "errors" => registration.errors.map { |e| { "code" => e.code, "message" => e.message } } }
            end
      # The oracle was created with the user in place; the rebuild's user is gone
      # when the transaction rolls back. Both are compared as plain data.
      next if got == expected

      "#{[login, email].inspect}\n    oracle:  #{expected.to_json}\n    rebuild: #{got.to_json}"
    end

    expect(divergences).to be_empty, "registration diverges from the oracle:\n\n#{divergences.join("\n")}"
  end

  it "creates the user with the default role and leaves the gate closed when asked to" do
    registration = run("fresh_user", "fresh_user@example.com")
    expect(registration).to be_success
    expect(registration.user.roles).to eq([payload.dig("fixtures", "settings", "default_role")])
    expect(registration.user.authentication_enabled?).to be(true)

    Configuration::Setting.set("users_can_register", "0")
    closed = run("another_user", "another_user@example.com")
    expect(closed).not_to be_success
    expect(closed.errors.map(&:code)).to eq(["registerdisabled"])
    expect(closed.errors.first.message).to eq("<strong>Error:</strong> User registration is currently not allowed.")
    expect(Identity::User.exists?(login: "another_user")).to be(false)
  end

  it "is reachable as the AGG-User command" do
    expect(Identity::User.register(login: "cmd_user", email: "cmd@example.com", login_url: login_url)).to be_success
  end
end
