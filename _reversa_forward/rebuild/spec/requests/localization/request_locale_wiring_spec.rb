# frozen_string_literal: true

require "rails_helper"

# The i18n WIRING: determine_locale() ran once per request off request globals; here each
# delivery surface states its own facts and Localization::Locale.determine decides. This
# proves, end to end through routing + middleware + the controller, that the RIGHT facts
# reach determine on each surface -- above all the BR-I18N-02 security boundary: a
# request-supplied wp_lang is honoured ONLY on the login screen.
RSpec.describe "Per-request locale wiring", type: :request do
  # Capture the keyword facts the surface handed determine_locale, then run the real thing.
  def capture_determine
    captured = nil
    allow(Localization::Locale).to receive(:determine).and_wrap_original do |orig, **kwargs|
      captured = kwargs
      orig.call(**kwargs)
    end
    yield
    captured
  end

  describe "the front end (site locale)" do
    it "resolves with all three surface predicates false and ignores a supplied wp_lang" do
      facts = capture_determine { get "/robots.txt", params: { wp_lang: "fr_FR" } }

      expect(response).to have_http_status(:ok)
      expect(facts).to include(admin: false, json_user_request: false, login_screen: false)
      # BR-I18N-02: wp_lang is passed but, off the login screen, contributes nothing.
      expect(Localization::Locale.determine(**facts)).to eq(Localization::Locale.site_locale)
    end
  end

  describe "the login screen (the wp_lang boundary)" do
    it "marks the request as the login surface and forwards the wp_lang value" do
      facts = capture_determine { get "/login", params: { wp_lang: "fr_FR" } }

      expect(response).to have_http_status(:ok)
      expect(facts).to include(login_screen: true, wp_lang_get: "fr_FR")
      # Here -- and only here -- the supplied value wins.
      expect(Localization::Locale.determine(**facts)).to eq("fr_FR")
    end

    it "sanitises the login wp_lang before it is used (BR-I18N-03)" do
      facts = capture_determine { get "/login", params: { wp_lang: "../es_ES" } }

      expect(Localization::Locale.determine(**facts)).to eq("es_ES")
    end
  end

  describe "a JSON REST request (?_locale=user)" do
    it "marks the request as a user-locale JSON request" do
      facts = capture_determine { get "/wp-json/", params: { _locale: "user" } }

      expect(facts).to include(json_user_request: true)
    end

    it "does not mark an ordinary REST request as user-locale" do
      facts = capture_determine { get "/wp-json/" }

      expect(facts).to include(json_user_request: false)
    end
  end

  # The console surface redirects an unauthenticated request to /login BEFORE the locale
  # resolves (auth_redirect is prepended), so its predicate is asserted at the unit level:
  # is_admin() is always true across the console, resolving to the user's locale.
  describe "the console surface predicate" do
    it "answers admin_surface? true" do
      expect(Console::BaseController.new.send(:admin_surface?)).to be(true)
    end
  end
end
