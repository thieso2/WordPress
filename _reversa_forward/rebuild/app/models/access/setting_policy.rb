# frozen_string_literal: true

module Access
  # Site settings: `manage_options`, the primitive every options screen checks
  # (wp-admin/options.php:42, `current_user_can( 'manage_options' )`).
  class SettingPolicy < BasePolicy
    def required_capabilities(action)
      %i[read edit set].include?(action.to_sym) ? ["manage_options"] : []
    end
  end
end
