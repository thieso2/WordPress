# frozen_string_literal: true

module Identity
  # AD-02: split out of wp_posts, where it lived as post_type = 'user_request'.
  #
  # The confirmation half -- wp_generate_user_request_key() (wp-includes/user.php:5052),
  # wp_validate_user_request_key() (:5082) and _wp_privacy_account_request_confirmed()
  # (:4244) -- is the `auth.confirmaction` screen's model. The legacy keeps the hashed
  # key in the request post's `post_password` and reads the key's age off
  # `post_modified_gmt` (:5091); here both are columns of their own
  # (db/migrate/20260822000110), because a modification timestamp that doubles as a
  # key-issue timestamp is exactly the kind of coincidence AD-03 exists to remove.
  class DataRequest < ApplicationRecord
    self.table_name = "data_requests"
    belongs_to :user, class_name: "Identity::User", optional: true
    KINDS = %w[export erasure].freeze
    validates :kind, inclusion: { in: KINDS }
    validates :email, presence: true

    # Legacy post_status values, minus the `request-` prefix the seeding pipeline
    # strips (lib/seeding/pipeline.rb load_data_requests).
    STATUSES = %w[pending confirmed failed completed].freeze

    # :5109 `apply_filters( 'user_request_key_expiration', DAY_IN_SECONDS )`, unfiltered.
    KEY_EXPIRATION = 1.day

    # wp_validate_user_request_key(), :5092-5119, in the legacy's order. Every string is
    # LITERAL; the codes are the legacy's.
    MESSAGES = {
      invalid_request: "Invalid personal data request.",
      expired_request: "This personal data request has expired.",
      missing_key: "The confirmation key is missing from this personal data request.",
      invalid_key: "The confirmation key is invalid for this personal data request.",
      expired_key: "The confirmation key has expired for this personal data request."
    }.freeze

    # wp_user_request_action_description(), :4863-4876.
    DESCRIPTIONS = { "export" => "Export Personal Data", "erasure" => "Erase Personal Data" }.freeze

    # _wp_privacy_account_request_confirmed_message(), :4757-4772. The generic pair is
    # the legacy's fallback for an unknown action; both kinds here are known.
    CONFIRMED_MESSAGES = {
      "export" => ["Thanks for confirming your export request.",
                   "The site administrator has been notified. You will receive a link to download your export via email when they fulfill your request."],
      "erasure" => ["Thanks for confirming your erasure request.",
                    "The site administrator has been notified. You will receive an email confirmation when they erase your data."],
      nil => ["Action has been confirmed.",
              "The site administrator has been notified and will fulfill your request as soon as possible."]
    }.freeze

    # wp_generate_user_request_key(), :5052-5066: a fresh 20-character key, the hash
    # stored, the status reset to pending. Returns the RAW key for the surface to mail.
    def issue_confirm_key!
      key = Identity::PasswordReset.generate_key
      update!(confirm_key_digest: Identity::PasswordReset.hash_key(key),
              confirm_key_sent_at: Time.current, status: "pending")
      key
    end

    # wp_validate_user_request_key(), :5082-5122. `request_id` may be anything the URL
    # carried; `absint()` makes it an integer (:5087) and an unknown id is an
    # invalid_request. Returns [request, nil] or [nil, code].
    def self.validate_key(request_id, key)
      request = find_by(id: request_id.to_s.to_i.abs)
      # :5093: no request, no saved key or no issue time -> invalid_request.
      return [nil, :invalid_request] if request.nil? || request.confirm_key_digest.blank? || request.confirm_key_sent_at.nil?
      return [nil, :expired_request] unless %w[pending failed].include?(request.status)
      # PHP `empty()`: "0" is empty too.
      return [nil, :missing_key] if key.to_s == "" || key.to_s == "0"

      unless ActiveSupport::SecurityUtils.secure_compare(Identity::PasswordReset.hash_key(key.to_s), request.confirm_key_digest)
        return [nil, :invalid_key]
      end
      return [nil, :expired_key] if Time.current > request.confirm_key_sent_at + KEY_EXPIRATION

      [request, nil]
    end

    # _wp_privacy_account_request_confirmed(), :4244-4262 -- the action the legacy
    # fires on `user_request_action_confirmed` (default-filters.php:453). Under AD-01
    # it is simply what confirming does. A request that is not pending/failed is left
    # alone (:4251).
    def confirm!
      return self unless %w[pending failed].include?(status)

      update!(status: "confirmed", confirmed_at: Time.current)
      self
    end

    def description = DESCRIPTIONS.fetch(kind, "Confirm the \"#{kind}\" action")

    def confirmed_message = CONFIRMED_MESSAGES.fetch(kind, CONFIRMED_MESSAGES[nil])
  end
end
