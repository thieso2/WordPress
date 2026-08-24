# frozen_string_literal: true

module Identity
  # AGG-User accepted commands `request_data_export` / `request_erasure`
  # (target_domain_model.md § AGG-User): wp_create_user_request(), wp-includes/user.php
  # :4803-4859. In the legacy a request is a wp_posts row of post_type 'user_request'
  # with the email in post_title and the action in post_name (BR-MIGRATE-039 exempts it
  # from slug uniqueness for that reason); AD-02 split it into Identity::DataRequest.
  #
  # The legacy action names stay the public vocabulary, mapped onto the target's kinds;
  # every string is LITERAL.
  class UserRequest
    Error = Struct.new(:code, :message, keyword_init: true)

    # _wp_privacy_action_request_types(), user.php:4009-4014, onto DataRequest::KINDS.
    ACTIONS = { "export_personal_data" => "export", "remove_personal_data" => "erasure" }.freeze

    # :4807-4817 and :4846.
    MESSAGES = {
      invalid_email:     "Invalid email address.",
      invalid_action:    "Invalid action name.",
      invalid_status:    "Invalid request status.",
      duplicate_request: "An incomplete personal data request for this email address already exists."
    }.freeze

    # :4815: only these two may be created directly; the others are reached by the
    # confirmation and completion flows.
    CREATABLE_STATUSES = %w[pending confirmed].freeze

    # :4829-4841: a duplicate is a request for the same email AND action that is still
    # open -- `request-pending` or `request-confirmed`.
    OPEN_STATUSES = %w[pending confirmed].freeze

    attr_reader :errors, :request

    def initialize(email:, action:, status: "pending")
      @email = Identity::UserRequest.sanitize_email(email)
      @action = Sanitizing::Formatting.sanitize_key(action.to_s)
      @status = status.to_s
      @errors = []
      @request = nil
    end

    def self.call(**) = new(**).call

    def success? = errors.empty? && request.present?

    def call
      return fail!(:invalid_email) unless Identity::Registration.email?(@email)
      return fail!(:invalid_action) unless ACTIONS.key?(@action)
      return fail!(:invalid_status) unless CREATABLE_STATUSES.include?(@status)

      kind = ACTIONS.fetch(@action)
      # :4819-4820: the request is attributed to the user holding that email, if any;
      # otherwise post_author is 0 -- NULL here.
      user = Identity::User.find_by(email: @email)

      return fail!(:duplicate_request) if Identity::DataRequest.where(email: @email, kind: kind,
                                                                       status: OPEN_STATUSES).exists?

      @request = Identity::DataRequest.create!(user: user, email: @email, kind: kind, status: @status,
                                               confirmed_at: (@status == "confirmed" ? Time.current : nil))
      self
    end

    # sanitize_email(), wp-includes/formatting.php:3831-3925, with the `sanitize_email`
    # filter removed (AD-01). Strips rather than rejects, then is_email() decides.
    def self.sanitize_email(email)
      email = email.to_s
      return "" if email.bytesize < 6                                   # email_too_short
      return "" if email.index("@", 1).nil?                             # email_no_at

      local, domain = email.split("@", 2)
      local = local.gsub(%r{[^a-zA-Z0-9!#$%&'*+/=?^_`{|}~.-]}, "")      # :3863
      return "" if local.empty?

      domain = domain.gsub(/\.{2,}/, "")                                # :3873
      return "" if domain.empty?

      domain = Identity::Registration.php_trim(domain, ".")             # :3880
      return "" if domain.empty?

      subs = domain.split(".", -1)
      return "" if subs.length < 2                                      # :3890

      new_subs = subs.map { |s| Identity::Registration.php_trim(s, "-").gsub(/[^a-z0-9-]+/i, "") }
                     .reject(&:empty?)
      return "" if new_subs.length < 2                                  # :3915

      "#{local}@#{new_subs.join('.')}"
    end

    private

    def fail!(code)
      errors << Error.new(code: code.to_s, message: MESSAGES.fetch(code))
      self
    end
  end
end
