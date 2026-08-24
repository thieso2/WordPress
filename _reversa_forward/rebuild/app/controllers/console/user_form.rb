# frozen_string_literal: true

module Console
  # The field-application half of edit_user() (wp-admin/includes/user.php:84-213), shared by
  # console.user-edit / console.user-new and console.profile. Only the fields the target
  # model keeps as columns are handled — email, url, display_name, locale, password. The
  # verbatim legacy validation strings live here (see the note on Console::UsersController).
  module UserForm
    extend ActiveSupport::Concern

    LANGUAGE_NONE = "site-default"

    private

    def apply_profile_fields(user)
      if params.key?(:email)
        email = params[:email].to_s
        if Identity::Registration.email?(email)
          owner = Identity::User.where.not(id: user.id).find_by(email: email)
          if owner
            add_error("<strong>Error:</strong> This email is already registered. Please choose another one.")
          else
            user.email = email
          end
        elsif email.empty?
          add_error("<strong>Error:</strong> Please enter an email address.")
        else
          add_error("<strong>Error:</strong> The email address is not correct.")
        end
      end

      user.url = normalize_url(params[:url]) if params.key?(:url)
      user.display_name = params[:display_name].to_s if params[:display_name].present?
      user.locale = normalize_locale(params[:locale]) if params.key?(:locale)
    end

    # includes/user.php:611-618: empty or the bare 'http://' clears the URL.
    def normalize_url(raw)
      value = raw.to_s.strip
      return nil if value.empty? || value == "http://"

      value.match?(%r{\A[a-z][a-z0-9+.\-]*://}i) ? value : "http://#{value}"
    end

    # includes/user.php:125-140: 'site-default' → nil (the site locale), '' → 'en_US'.
    def normalize_locale(raw)
      value = raw.to_s
      return nil if value.empty? || value == LANGUAGE_NONE

      value
    end

    # includes/user.php:47-70 + :180-213: password congruity and the backslash rule.
    def apply_password(user, update:)
      pass1 = params[:pass1].to_s.strip
      pass2 = params[:pass2].to_s.strip

      if !update && pass1.empty?
        add_error("<strong>Error:</strong> Please enter a password.")
        return
      end
      if pass1.include?("\\")
        add_error('<strong>Error:</strong> Passwords may not contain the character "\\".')
        return
      end
      if (update || !pass1.empty?) && pass1 != pass2
        add_error("<strong>Error:</strong> Passwords do not match. Please enter the same password in both password fields.")
        return
      end
      user.password = pass1 unless pass1.empty?
    end

    def collect_model_errors(user)
      @form_errors.concat(user.errors.full_messages) if @form_errors.empty?
    end

    def add_error(html) = @form_errors << html
  end
end
