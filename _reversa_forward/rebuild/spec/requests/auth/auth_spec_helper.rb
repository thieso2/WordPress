# frozen_string_literal: true

require "rails_helper"
require "nokogiri"
require "open3"
require_relative "support/oracle_http"

# Shared fixture for the auth request specs: the oracle's corpus users, re-created in
# the private test database with the same logins, emails, roles and passwords
# (tools/seed.php), so a request here and the same request against the oracle address
# the same account.
module AuthSpecHelper
  def seed_oracle_users!
    AuthOracle::USERS.each do |login, attrs|
      user = Identity::User.create!(login: login, email: attrs[:email], nicename: login.tr("_", "-"),
                                    display_name: login, password: attrs[:password])
      user.assign_role(attrs[:role])
    end
    Configuration::Setting.set("blogname", "Reversa Oracle &quot;7.2&quot; 😀")
    Configuration::Setting.set("admin_email", "oracle@example.com")
    Configuration::Setting.set("users_can_register", "0")
    Configuration::Setting.set("default_role", "subscriber")
  end

  def doc = Nokogiri::HTML(response.body)
  def error_notice = AuthOracle.normalize(doc.at_css("#login_error")&.inner_html)
  def message_notice = AuthOracle.normalize(doc.at_css("#login-message")&.inner_html)
  def page_title = doc.at_css("title")&.text.to_s
  def field(id) = doc.at_css("##{id}")&.[]("value")
  def aria(id) = doc.at_css("##{id}")&.[]("aria-describedby")

  # The test cookie wp-login.php:405 sets on the GET and :1357 expects back.
  def with_test_cookie
    cookies[Auth::SessionCookie::TEST_COOKIE] = Auth::SessionCookie::TEST_COOKIE_VALUE
  end

  # The raw session token inside the encrypted cookie -- what Identity::Nonce binds to.
  def session_token_from_cookies
    jar = ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
    jar.encrypted[Auth::SessionCookie::COOKIE]
  end

  def oracle_available? = AuthOracle.available?

  # The rolled-back PHP bridge (support/auth_oracle.php). Each op mutates wp_users /
  # wp_usermeta inside a transaction that is rolled back, so a write-path differential
  # never dirties the shared corpus (RISK-002). Returns the parsed results, one per op.
  AUTH_BRIDGE = File.expand_path("support/auth_oracle.php", __dir__)
  BOOTSTRAP_PATH = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"

  def auth_bridge(*ops)
    stdin = ops.map { |o| JSON.generate(o) }.join("\n")
    out, err, status = Open3.capture3({ "WP_ORACLE_BOOTSTRAP" => BOOTSTRAP_PATH }, "php", AUTH_BRIDGE, stdin_data: stdin)
    raise "auth_oracle.php failed (#{status.exitstatus}): #{err}" unless status.success?

    JSON.parse(out)
  end
end

RSpec.configure do |config|
  config.include AuthSpecHelper, type: :request
  config.include ActiveSupport::Testing::TimeHelpers, type: :request
end
