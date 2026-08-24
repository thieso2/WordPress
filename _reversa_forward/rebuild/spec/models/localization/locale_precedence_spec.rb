# frozen_string_literal: true

require "rails_helper"

# determine_locale()'s full precedence (l10n.php:124-176 / BR-I18N-01..05,
# BR-MIGRATE-283..287). The differential spec drives the branches is_admin() leaves false
# (login boundary, sanitize, fallback); this spec covers the branches that need is_admin()
# or wp_installing() true -- unreachable in one oracle CLI process -- as a faithful
# transcription of the legacy control flow, plus the effective-locale reader.
RSpec.describe Localization::Locale do
  before { Localization::Current.reset }

  # A user carrying its own locale column (users.locale, AD-01's promoted meta). nil = "use
  # the site locale", the legacy's empty user meta (get_user_locale, l10n.php:105).
  def user_with(locale) = Struct.new(:id, :locale).new(7, locale)

  describe ".determine precedence" do
    # BR-I18N-04 / BR-MIGRATE-286: is_admin() -> the user's locale.
    it "returns the user's locale on the admin surface" do
      result = described_class.determine(admin: true, json_user_request: false, login_screen: false,
                                         user: user_with("fr_FR"))
      expect(result).to eq("fr_FR")
    end

    # A ?_locale=user JSON request is the user's locale even off the admin surface.
    it "returns the user's locale for a ?_locale=user JSON request" do
      result = described_class.determine(admin: false, json_user_request: true, login_screen: false,
                                         user: user_with("de_DE"))
      expect(result).to eq("de_DE")
    end

    # A user with no locale of their own falls to the site locale (get_user_locale, :105).
    it "falls to the site locale when the admin user has no locale" do
      allow(described_class).to receive(:site_locale).and_return("es_ES")
      result = described_class.determine(admin: true, json_user_request: false, login_screen: false,
                                         user: user_with(nil))
      expect(result).to eq("es_ES")
    end

    # BR-I18N-02 / BR-MIGRATE-284: the login screen is the ONLY surface honouring wp_lang.
    # GET wins over cookie; the value is sanitised (BR-I18N-03).
    it "honours a sanitised wp_lang GET only on the login screen, GET over cookie" do
      result = described_class.determine(admin: false, json_user_request: false, login_screen: true,
                                         wp_lang_get: "../fr_FR", wp_lang_cookie: "de_DE")
      expect(result).to eq("fr_FR")
    end

    it "ignores wp_lang entirely off the login screen (the security boundary)" do
      allow(described_class).to receive(:site_locale).and_return("en_US")
      result = described_class.determine(admin: false, json_user_request: false, login_screen: false,
                                         wp_lang_get: "fr_FR", wp_lang_cookie: "de_DE")
      expect(result).to eq("en_US")
    end

    # BR-I18N-05 / BR-MIGRATE-287: the installer branch. No live web-install surface in the
    # target, kept for faithfulness; sanitised like every other request value.
    it "uses the sanitised installing language during installation" do
      result = described_class.determine(admin: false, json_user_request: false, login_screen: false,
                                         installing: true, installing_language: "pt_BR/../x")
      expect(result).to eq("pt_BRx")
    end

    it "falls to the site locale when nothing else applies" do
      allow(described_class).to receive(:site_locale).and_return("en_US")
      result = described_class.determine(admin: false, json_user_request: false, login_screen: false)
      expect(result).to eq("en_US")
    end
  end

  describe ".current effective locale" do
    it "prefers a live switch over the request base over the site locale" do
      allow(described_class).to receive(:site_locale).and_return("en_US")

      expect(described_class.current).to eq("en_US")           # off the request path

      Localization::Current.request_locale = "de_DE"
      expect(described_class.current).to eq("de_DE")           # request base

      Localization::Current.push("fr_FR", nil)
      expect(described_class.current).to eq("fr_FR")           # top of the switch stack
    end
  end

  describe ".available?" do
    # array_merge( array('en_US'), get_available_languages() ): en_US is always available;
    # nothing else is installed today (Catalogue.installed_locales == []).
    it "accepts en_US and rejects an uninstalled locale" do
      expect(described_class.available?("en_US")).to be(true)
      expect(described_class.available?("fr_FR")).to be(false)
    end
  end
end
