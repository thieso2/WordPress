# frozen_string_literal: true

module Tenancy
  # wp-activate.php — the two activation screens (target_screens.md Part 6):
  #   * tenancy.activate_form   GET  /activate       — the activation-key form
  #   * tenancy.activate_result GET  /activate/done  — message + credentials
  # POST /activate consumes the key: Tenancy::Signup#activate! creates the user and (for a
  # blog signup) provisions the new PostgreSQL schema (Tenancy::Provisioner), which is why
  # this whole concern is sequenced last (RISK-009).
  class ActivationsController < BaseController
    # tenancy.activate_form. wp-activate.php:120-138 — the "Activation Key Required" form.
    # A `key` in the query (the link from the confirmation email) activates immediately;
    # otherwise the form is shown for manual entry.
    def form
      @activation_key = params[:key].to_s
      @error = nil
      return activate_key(@activation_key) if @activation_key.present?

      render :form
    end

    # POST /activate — manual key submission.
    def create
      activate_key(params[:key].to_s.strip)
    end

    # tenancy.activate_result. Rendered by activate_key on success; also reachable directly
    # after a redirect (rare — the result carries a one-time password, so the success render
    # is inline).
    def done
      render :done
    end

    private

    def activate_key(key)
      @activation_key = key
      signup = Tenancy::Signup.find_by(activation_key: key)

      # wp-activate.php:29-31: a missing/mismatched key is the activation error.
      if signup.nil?
        @error = "A key value mismatch has been detected. Please follow the link provided in your activation email."
        return render(:form, status: :unprocessable_content)
      end

      result = signup.activate!
      @user = result.user
      @site = result.site
      @password = result.password
      @already_active = result.password.nil?
      render :done
    rescue ActiveRecord::RecordInvalid, Tenancy::InvalidSchemaName => e
      @error = "An error occurred during the activation. #{e.message}"
      render :form, status: :unprocessable_content
    end
  end
end
