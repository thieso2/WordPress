# frozen_string_literal: true

module Console
  # console.privacy-policy-guide — wp-admin/privacy-policy-guide.php (target_screens.md:557).
  # Static guidance. privacy-policy-guide.php gates on `manage_privacy_options` (maps to
  # `manage_options` on a single site).
  class PrivacyGuideController < BaseController
    include Chrome

    DENIED = "Sorry, you are not allowed to manage privacy options on this site."

    before_action -> { require_capability!("manage_privacy_options", DENIED) }

    def show; end
  end
end
