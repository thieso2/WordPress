# frozen_string_literal: true

module Assistance
  # A registered ability and its execution pipeline. Reproduces WP_Ability
  # (wp-includes/abilities-api/class-wp-ability.php).
  #
  # Reproduced OBSERVABLE behaviour:
  #   * BR-MIGRATE-272 (BR-AI-04): `public` and `show_in_rest` default to FALSE — the opposite
  #     of register_rest_route()'s default. `show_in_rest` is seeded from `public` when `public`
  #     is set explicitly, else falls to false (class-wp-ability.php:370-371).
  #   * BR-MIGRATE-273 (BR-AI-05): execute() runs, in order,
  #     normalize_input -> validate_input -> check_permissions -> do_execute -> validate_output
  #     (class-wp-ability.php:769).
  #   * BR-MIGRATE-275 (BR-AI-07): permissions are checked AFTER input validation, so a malformed
  #     request is rejected before authorization ever runs (class-wp-ability.php:623).
  #   * BR-MIGRATE-274 (BR-AI-06): input and output are validated against JSON Schema.
  #   * BR-MIGRATE-276 (BR-AI-08): __wakeup/__sleep were PHP unserialization guards because the
  #     object holds callables. Ruby's Marshal is not used here and the pipeline never serializes
  #     an ability, so the guard is ABSORBED — there is nothing to defend. `callback` procs make
  #     Marshal.dump raise on its own; we do not add a bespoke guard.
  #
  # Every legacy execution stage also fired filters/actions (wp_ability_normalize_input,
  # wp_ability_validate_input, wp_ability_permission_result, wp_ability_execute_result,
  # wp_before_execute_ability, ...). AD-01 removed the hook system: each stage here implements the
  # pre-filter DEFAULT only, with no extension point.
  class Ability
    NAME_PATTERN = /\A[a-z0-9-]+\/[a-z0-9-]+\z/ # class-wp-abilities-registry.php:86

    class InvalidArgument < StandardError; end

    attr_reader :name, :label, :description, :category, :input_schema, :output_schema, :meta

    # @param permission_callback [#call] returns true/false (a Result error also denies).
    # @param execute_callback    [#call] returns the ability's output value (or a Result on failure).
    def initialize(name, label:, description:, category:, execute_callback:, permission_callback:,
                   input_schema: {}, output_schema: {}, meta: {})
      raise InvalidArgument, "The ability properties must contain a `label` string." unless nonempty_string?(label)
      raise InvalidArgument, "The ability properties must contain a `description` string." unless nonempty_string?(description)
      raise InvalidArgument, "The ability properties must contain a `category` string." unless nonempty_string?(category)
      raise InvalidArgument, "The ability properties must contain a valid `execute_callback` function." unless execute_callback.respond_to?(:call)
      raise InvalidArgument, "The ability properties must provide a valid `permission_callback` function." unless permission_callback.respond_to?(:call)
      raise InvalidArgument, "The ability properties should provide a valid `input_schema` definition." unless input_schema.is_a?(Hash)
      raise InvalidArgument, "The ability properties should provide a valid `output_schema` definition." unless output_schema.is_a?(Hash)

      @name = name
      @label = label
      @description = description
      @category = category
      @execute_callback = execute_callback
      @permission_callback = permission_callback
      @input_schema = input_schema
      @output_schema = output_schema
      @meta = resolve_meta(meta)
      freeze
    end

    def public?
      @meta.fetch(:public)
    end

    def show_in_rest?
      @meta.fetch(:show_in_rest)
    end

    # BR-MIGRATE-273 / BR-MIGRATE-275: the pipeline, in exact order.
    # @return [Result]
    def execute(input = nil)
      input = normalize_input(input)

      input_check = validate_input(input)
      return input_check if input_check.error?

      # Permissions come AFTER input validation (BR-AI-07): a malformed request never reaches
      # authorization. Reordering these two lines is the whole point of the rule.
      permission = check_permissions(input)
      unless permission == true
        return Result.error(
          "ability_invalid_permissions",
          %(Ability "#{name}" does not have necessary permission.)
        )
      end

      result = do_execute(input)
      return result if result.is_a?(Result) && result.error?

      output = result.is_a?(Result) ? result.value : result

      output_check = validate_output(output)
      return output_check if output_check.error?

      Result.ok(output)
    end

    # --- pipeline stages (public, matching class-wp-ability.php's public surface) ---

    # normalize_input(): apply the input schema's `default` when no input was given. The legacy
    # then ran the wp_ability_normalize_input filter (7.1.0); AD-01 removed it, so this is the
    # pre-filter default only.
    def normalize_input(input = nil)
      if input.nil?
        schema = stringify(@input_schema)
        return schema["default"] if schema.key?("default")
      end
      input
    end

    def validate_input(input = nil)
      if @input_schema.nil? || @input_schema.empty?
        return Result.ok(true) if input.nil?

        return Result.error(
          "ability_missing_input_schema",
          %(Ability "#{name}" does not define an input schema required to validate the provided input.)
        )
      end

      reason = SchemaValidator.validate(input, @input_schema, "input")
      return Result.ok(true) if reason.nil?

      Result.error("ability_invalid_input", %(Ability "#{name}" has invalid input. Reason: #{reason}))
    end

    def check_permissions(input = nil)
      result = invoke_callback(@permission_callback, input)
      # class-wp-ability.php:640 — anything that is not a bool (and here, not a denying Result)
      # is coerced to false.
      return result if result == true || result == false
      return false if result.is_a?(Result) # a Result error denies; nothing grants but true
      false
    end

    def validate_output(output)
      return Result.ok(true) if @output_schema.nil? || @output_schema.empty?

      reason = SchemaValidator.validate(output, @output_schema, "output")
      return Result.ok(true) if reason.nil?

      Result.error("ability_invalid_output", %(Ability "#{name}" has invalid output. Reason: #{reason}))
    end

    private

    def do_execute(input = nil)
      invoke_callback(@execute_callback, input)
    end

    # class-wp-ability.php:582 invoke_callback(): input is passed to the callback ONLY when an
    # input schema is defined; a schemaless ability is called with no arguments. A thrown error
    # becomes an ability_callback_exception Result (class-wp-ability.php:596).
    def invoke_callback(callback, input)
      args = (@input_schema.nil? || @input_schema.empty?) ? [] : [input]
      callback.call(*args)
    rescue StandardError => e
      Result.error(
        "ability_callback_exception",
        %(Ability "#{name}" callback threw an exception: #{e.message})
      )
    end

    def resolve_meta(meta)
      meta = (meta || {}).transform_keys(&:to_sym)
      has_public = meta.key?(:public)
      has_rest = meta.key?(:show_in_rest)

      public_flag = has_public ? !!meta[:public] : false                       # DEFAULT_PUBLIC = false
      show_in_rest = if has_rest
                       !!meta[:show_in_rest]
                     elsif has_public
                       public_flag                                             # `public` seeds it
                     else
                       false                                                   # DEFAULT_SHOW_IN_REST
                     end

      meta.merge(public: public_flag, show_in_rest: show_in_rest).freeze
    end

    def nonempty_string?(value)
      value.is_a?(String) && !value.empty?
    end

    def stringify(schema)
      (schema || {}).each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end
  end
end
