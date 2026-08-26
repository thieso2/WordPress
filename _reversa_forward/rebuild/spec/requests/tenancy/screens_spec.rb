# frozen_string_literal: true

require "rails_helper"
require_relative "../../tenancy/tenancy_helper"

# The 5 Wave 5 screens (target_screens.md Part 6), end to end through routing + AD-04 + the
# controllers. MODERNIZED mode — not byte-parity — so these assert the states and the legacy
# verbatim copy, not a golden.
RSpec.describe "Tenancy signup/activation screens", type: :request do
  include TenancyHelper

  context "with multisite disabled (single-site default)" do
    it "answers /signup with the legacy 'disabled' state, not a 404" do
      get "/signup"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Registration has been disabled.")
    end

    it "answers /activate with the disabled state too" do
      get "/activate"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Registration has been disabled.")
    end
  end

  context "with multisite enabled" do
    around { |example| with_multisite { example.run } }

    it "tenancy.user_signup renders the account form" do
      get "/signup"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Username:")
      expect(response.body).to include("account in seconds")
    end

    it "tenancy.blog_signup renders the site form" do
      get "/signup/site"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Site Domain:")
      expect(response.body).to include("Allow search engines to index this site.")
    end

    it "POST /signup writes a Signup and redirects to the confirmation" do
      expect do
        post "/signup", params: { signup_for: "blog", user_name: "newbie", user_email: "newbie@example.com",
                                  blogname: "newbie.example", blog_title: "Newbie" }
      end.to change(Tenancy::Signup, :count).by(1)
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(response.body).to include("you must activate it")
    end

    it "POST /signup surfaces validation errors verbatim" do
      post "/signup", params: { signup_for: "user", user_name: "", user_email: "not-an-email" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Please enter a username.")
    end

    it "tenancy.activate_form renders the key form" do
      get "/activate"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Activation Key Required")
    end

    it "activating a valid key shows the result with credentials" do
      signup = Tenancy::Signup.create!(kind: "blog", user_login: "done", user_email: "done@example.com",
                                       domain: "done.example", path: "/", title: "Done")
      get "/activate", params: { key: signup.activation_key }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your account is now active!")
      expect(response.body).to include("Username:")
    end

    it "a bad key shows the activation error verbatim" do
      post "/activate", params: { key: "nope" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("A key value mismatch has been detected")
    end

    # ── RISK-023 V5 ────────────────────────────────────────────────────────────────
    # confirm_blog_signup() prints the address RAW (wp-signup.php:893, no esc_html) and the
    # view reproduces that faithfully. What made it exploitable was this side: the action
    # redirected and then read the address back out of the QUERY STRING. The legacy hands
    # confirm_*_signup() the address it validated in the same request; nothing in it ever
    # travels through a URL.
    it "renders the PERSISTED email, never what the query string carries" do
      signup = Tenancy::Signup.create!(kind: "blog", user_login: "victim", user_email: "victim@example.com",
                                       domain: "victim.example", path: "/", title: "Victim")

      get "/signup/confirm", params: { key: signup.activation_key,
                                       email: "<script>alert(1)</script>" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(response.body).to include("victim@example.com")
    end

    # The same for the user branch, which reaches the address through content_tag and was
    # never injectable — pinned so it stays that way.
    it "renders the persisted email on the user-signup branch too" do
      signup = Tenancy::Signup.create!(kind: "user", user_login: "solo", user_email: "solo@example.com")

      get "/signup/confirm", params: { key: signup.activation_key,
                                       email: "<script>alert(1)</script>" }

      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(response.body).to include("solo@example.com")
    end
  end
end
