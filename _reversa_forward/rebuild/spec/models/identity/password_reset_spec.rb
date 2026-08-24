# frozen_string_literal: true

require "rails_helper"

# Identity::PasswordReset -- the key lifecycle of get_password_reset_key() /
# check_password_reset_key() (wp-includes/user.php:3099, :3175) and the form rules of
# wp-login.php:990-1001. The strings are compared against the oracle over HTTP in
# spec/requests/auth/; this is the model's own contract.
RSpec.describe Identity::PasswordReset do
  include ActiveSupport::Testing::TimeHelpers

  let!(:user) do
    Identity::User.create!(login: "reset_me", email: "reset_me@example.com", nicename: "reset-me",
                           display_name: "reset_me", password: "original-pw")
  end

  describe ".request" do
    it "refuses an empty identifier with empty_username" do
      r = described_class.request("   ")
      expect(r.errors.codes).to eq(["empty_username"])
    end

    it "answers invalid_email for an unknown email and invalidcombo for an unknown login, same string" do
      email = described_class.request("nobody@example.com")
      login = described_class.request("nobody")
      expect(email.errors.codes).to eq(["invalid_email"])
      expect(login.errors.codes).to eq(["invalidcombo"])
      expect(email.errors.messages).to eq(login.errors.messages)
    end

    it "issues a 20-character alphanumeric key for a known login or email" do
      r = described_class.request("reset_me@example.com")
      expect(r).to be_success
      expect(r.key).to match(/\A[A-Za-z0-9]{20}\z/)
      expect(described_class.check(r.key, "reset_me").first).to eq(user)
    end
  end

  describe ".check" do
    it "strips characters outside [a-z0-9] from the key before checking (user.php:3180)" do
      key = described_class.issue_key!(user)
      expect(described_class.check("#{key[0, 10]}-#{key[10, 10]}", "reset_me").first).to eq(user)
    end

    it "answers invalid_key for an empty key, an unknown login, or a user with no key" do
      expect(described_class.check("", "reset_me")).to eq([nil, :invalid_key])
      expect(described_class.check("abc", "nobody")).to eq([nil, :invalid_key])
      expect(described_class.check("abc", "reset_me")).to eq([nil, :invalid_key])
    end

    it "replaces the previous key on reissue" do
      first = described_class.issue_key!(user)
      second = described_class.issue_key!(user)
      expect(described_class.check(first, "reset_me")).to eq([nil, :invalid_key])
      expect(described_class.check(second, "reset_me").first).to eq(user)
    end

    it "expires after DAY_IN_SECONDS with expired_key, and is valid up to that instant" do
      key = described_class.issue_key!(user)
      travel(23.hours + 59.minutes) { expect(described_class.check(key, "reset_me").first).to eq(user) }
      travel(24.hours + 1.second) { expect(described_class.check(key, "reset_me")).to eq([nil, :expired_key]) }
    end

    it "treats a legacy key stored without a timestamp as expired (user.php:3236)" do
      user.update_column(:activation_key_digest, described_class.hash_key("legacykey0000000000x"))
      expect(described_class.check("legacykey0000000000x", "reset_me")).to eq([nil, :expired_key])
    end
  end

  describe ".validate" do
    it "trims pass1 and reports all-spaces and mismatches with the legacy strings" do
      expect(described_class.validate("   ", "   ").last.codes).to eq(["password_reset_empty_space"])
      expect(described_class.validate("abc", "abd").last.codes).to eq(["password_reset_mismatch"])
      expect(described_class.validate(" abc ", "abc").last).to be_empty
      expect(described_class.validate(" abc ", "abc").first).to eq("abc")
    end

    it "treats an empty or '0' pass1 as not submitted (PHP empty())" do
      %w[0].push("").each do |v|
        trimmed, errors = described_class.validate(v, "anything")
        expect(errors).to be_empty
        expect(described_class.submitted?(trimmed)).to be(false)
      end
    end
  end

  describe ".reset!" do
    it "changes the digest, clears the key and destroys every session" do
      key = described_class.issue_key!(user)
      token = user.start_session!
      described_class.reset!(user, "new-pw-123")
      expect(user.reload.authenticate("new-pw-123")).to be_truthy
      expect(user.activation_key_digest).to be_nil
      expect(Identity::Session.authenticate(token)).to be_nil
      expect(described_class.check(key, "reset_me")).to eq([nil, :invalid_key])
    end
  end

  describe "Identity::User#record_login!" do
    it "voids an outstanding key (wp_signon(), user.php:122)" do
      key = described_class.issue_key!(user)
      user.record_login!
      expect(described_class.check(key, "reset_me")).to eq([nil, :invalid_key])
    end
  end

  describe "Identity::User.authenticate_login" do
    it "rehashes a legacy digest on success, which signs every OTHER device out (BR-AUTH-05 via T-10)" do
      user.update_column(:password_digest, "$2y$12$ljaQG3kaFlPktWggQnzg8.79Vov1N8k8yCidSGZ3L7rq.ScDj1cFm")
      other = user.start_session!
      found, errors = Identity::User.authenticate_login("reset_me", "correct horse battery staple", lost_password_url: "/x")
      expect(errors).to be_nil
      expect(found).to eq(user)
      expect(user.reload.password_digest).to start_with(Identity::LegacyDigest::TARGET_PREFIX)
      expect(Identity::Session.authenticate(other)).to be_nil
    end

    it "reports the legacy codes in the legacy order" do
      expect(Identity::User.authenticate_login("", "", lost_password_url: "/x").last.codes).to eq(%w[empty_username empty_password])
      expect(Identity::User.authenticate_login("reset_me", "", lost_password_url: "/x").last.codes).to eq(%w[empty_password])
      expect(Identity::User.authenticate_login("nobody", "x", lost_password_url: "/x").last.codes).to eq(%w[invalid_username])
      expect(Identity::User.authenticate_login("nobody@example.com", "x", lost_password_url: "/x").last.codes).to eq(%w[invalid_email])
      expect(Identity::User.authenticate_login("reset_me", "wrong", lost_password_url: "/x").last.codes).to eq(%w[incorrect_password])
      expect(Identity::User.authenticate_login("reset_me@example.com", "wrong", lost_password_url: "/x").last.codes).to eq(%w[incorrect_password])
    end
  end
end
