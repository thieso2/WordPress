# frozen_string_literal: true

require_relative "auth_spec_helper"

# auth.confirmaction -- wp-login.php `case 'confirmaction'` (:1237-1274),
# wp_validate_user_request_key() (user.php:5082), _wp_privacy_account_request_confirmed()
# (:4244) and the confirmed message (:4757).
#
# DIFFERENTIAL for the strings the oracle shows without a key of its own: the seeded
# user_request row carries no confirm key, so the oracle answers "Missing request ID.",
# "Missing confirm key." and "Invalid personal data request." and nothing further. The
# key-bound outcomes are asserted on the rebuild with the literal strings from user.php.
RSpec.describe "auth.confirmaction", type: :request do
  before do
    skip "the PHP oracle is not available" unless oracle_available?
    seed_oracle_users!
    host! "127.0.0.1"
    ActionMailer::Base.deliveries.clear
    @request_record = Identity::DataRequest.create!(user: Identity::User.find_by!(login: "oracle_editor"),
                                                    email: "oracle_editor@example.com", kind: "export", status: "pending")
    @key = @request_record.issue_confirm_key!
  end

  def oracle_die_message(query)
    AuthOracle.get("/wp-login.php?action=confirmaction#{query}").doc.at_css(".wp-die-message")&.text
  end

  it "answers the missing-parameter cases with the oracle's strings" do
    expect(oracle_die_message("")).to eq("Missing request ID.")
    get "/login/confirm"
    expect(response).to have_http_status(:unprocessable_content)
    expect(error_notice).to eq("<p>Missing request ID.</p>")

    expect(oracle_die_message("&request_id=1")).to eq("Missing confirm key.")
    get "/login/confirm", params: { request_id: @request_record.id }
    expect(error_notice).to eq("<p>Missing confirm key.</p>")
  end

  it "answers an unknown request with the oracle's string" do
    expect(oracle_die_message("&request_id=99999&confirm_key=abc")).to eq("Invalid personal data request.")
    get "/login/confirm", params: { request_id: 99_999, confirm_key: "abc" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(error_notice).to eq("<p>Invalid personal data request.</p>")
  end

  it "answers a request that never had a key issued with invalid_request, as the oracle's seeded row does" do
    bare = Identity::DataRequest.create!(email: "guest@example.com", kind: "erasure", status: "pending")
    get "/login/confirm", params: { request_id: bare.id, confirm_key: "abc" }
    expect(error_notice).to eq("<p>Invalid personal data request.</p>")
  end

  it "answers a wrong, empty, expired or already-confirmed key with the legacy strings (user.php:5097-5119)" do
    get "/login/confirm", params: { request_id: @request_record.id, confirm_key: "wrongkey" }
    expect(error_notice).to eq("<p>The confirmation key is invalid for this personal data request.</p>")

    get "/login/confirm", params: { request_id: @request_record.id, confirm_key: "" }
    expect(error_notice).to eq("<p>The confirmation key is missing from this personal data request.</p>")

    travel 25.hours do
      get "/login/confirm", params: { request_id: @request_record.id, confirm_key: @key }
      expect(error_notice).to eq("<p>The confirmation key has expired for this personal data request.</p>")
    end

    @request_record.update!(status: "completed")
    get "/login/confirm", params: { request_id: @request_record.id, confirm_key: @key }
    expect(error_notice).to eq("<p>This personal data request has expired.</p>")
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "confirms the request, notifies the administrator and shows the export message" do
    get "/login/confirm", params: { request_id: @request_record.id, confirm_key: @key }
    expect(response).to have_http_status(:ok)
    expect(page_title).to start_with("User action confirmed.")
    expect(response.body).to include("Thanks for confirming your export request.")
      .and include("The site administrator has been notified. You will receive a link to download your export via email when they fulfill your request.")
    expect(@request_record.reload.status).to eq("confirmed")
    expect(@request_record.confirmed_at).to be_present

    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq(["oracle@example.com"])
    expect(mail.subject).to eq("[Reversa Oracle \"7.2\" 😀] Action Confirmed: Export Personal Data")
    expect(mail.body.decoded).to include("A user data privacy request has been confirmed on Reversa Oracle \"7.2\" 😀:")
      .and include("User: oracle_editor@example.com").and include("Request: Export Personal Data")

    # A confirmed request is no longer pending: the same link now reports expiry.
    get "/login/confirm", params: { request_id: @request_record.id, confirm_key: @key }
    expect(error_notice).to eq("<p>This personal data request has expired.</p>")
  end

  it "shows the erasure message for an erasure request" do
    erasure = Identity::DataRequest.create!(email: "guest@example.com", kind: "erasure", status: "pending")
    key = erasure.issue_confirm_key!
    get "/login/confirm", params: { request_id: erasure.id, confirm_key: key }
    expect(response.body).to include("Thanks for confirming your erasure request.")
      .and include("The site administrator has been notified. You will receive an email confirmation when they erase your data.")
    expect(ActionMailer::Base.deliveries.last.subject).to end_with("Action Confirmed: Erase Personal Data")
  end
end
