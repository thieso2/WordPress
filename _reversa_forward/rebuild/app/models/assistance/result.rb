# frozen_string_literal: true

module Assistance
  # The abilities pipeline returns either a value or a failure. The legacy expresses this
  # with the "return the value, or a WP_Error" convention (class-wp-ability.php:769); WP_Error
  # is the framework's own type and is gone here (AD-01 removed the hook system it travelled
  # with, and the migration replaces WP_Error with an explicit result object).
  #
  # A bare "value or error object" union is ambiguous in Ruby the moment an ability legitimately
  # returns something error-shaped, so the pipeline is total: every stage returns a Result. The
  # error *codes* are reproduced verbatim from the oracle (ability_invalid_input,
  # ability_invalid_permissions, ability_missing_input_schema, ability_invalid_output,
  # ability_callback_exception, ability_invalid_permission_callback) so callers observe the same
  # contract.
  class Result
    attr_reader :value, :code, :message, :data

    def self.ok(value = nil)
      new(ok: true, value: value)
    end

    def self.error(code, message = nil, data: nil)
      new(ok: false, code: code, message: message, data: data)
    end

    def initialize(ok:, value: nil, code: nil, message: nil, data: nil)
      @ok = ok
      @value = value
      @code = code
      @message = message
      @data = data
      freeze
    end

    def ok?
      @ok
    end

    def error?
      !@ok
    end
  end
end
