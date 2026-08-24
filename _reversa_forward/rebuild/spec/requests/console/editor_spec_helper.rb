# frozen_string_literal: true

require "rails_helper"
require "nokogiri"
require "active_support/testing/time_helpers"

# Fixture for the EDITOR request specs (console.post / console.post-new / console.site-editor).
# Kept separate from the P-EDIT track's ConsoleSpecHelper to avoid a shared-file collision;
# the editor is a distinct screen family with its own needs (an administrator, for the site
# editor's edit_theme_options gate, which the oracle corpus has no user for).
#
# Self-contained: it seeds its own users and logs in over the real login surface (POST
# /login), so a console request carries a genuine session cookie and current_actor resolves
# exactly as in production. No oracle dependency — the editor's client half is compiled JS
# (DEV-012); these specs verify the SERVER-SIDE contract, the half this pass builds.
module EditorSpecHelper
  EDITOR_ROLE_PASSWORDS = {
    "administrator" => "pw-admin-1",
    "editor" => "pw-editor-1",
    "author" => "pw-author-1",
    "subscriber" => "pw-sub-1"
  }.freeze

  def seed_editor_users!
    EDITOR_ROLE_PASSWORDS.each do |role, password|
      login = "editspec_#{role}"
      u = Identity::User.create!(login: login, email: "#{login}@example.com",
                                 nicename: login.tr("_", "-"), display_name: "Console #{role.titleize}",
                                 password: password)
      u.assign_role(role)
    end
    Configuration::Setting.set("blogname", "Reversa Rebuild")
  end

  def editor_user(role) = Identity::User.find_by!(login: "editspec_#{role}")

  # wp-login.php:405 sets the test cookie on the GET; :1357 expects it back on submit.
  def sign_in_as(role)
    cookies[Auth::SessionCookie::TEST_COOKIE] = Auth::SessionCookie::TEST_COOKIE_VALUE
    post "/login", params: { log: "editspec_#{role}", pwd: EDITOR_ROLE_PASSWORDS.fetch(role), testcookie: "1" }
    raise "sign_in_as(#{role}) failed: #{response.status}" unless response.status == 303
  end

  def sign_out
    cookies.delete(Auth::SessionCookie::COOKIE)
  end

  def edoc = Nokogiri::HTML(response.body)
end

RSpec.configure do |config|
  config.include EditorSpecHelper, type: :request
  config.include ActiveSupport::Testing::TimeHelpers, type: :request
end
