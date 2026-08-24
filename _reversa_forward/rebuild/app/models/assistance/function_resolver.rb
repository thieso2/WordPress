# frozen_string_literal: true

module Assistance
  # BR-MIGRATE-278 (BR-AI-10): registered abilities are exposed to AI models as callable
  # functions. Reproduces WP_AI_Client_Ability_Function_Resolver
  # (wp-includes/ai-client/class-wp-ai-client-ability-function-resolver.php).
  #
  # The resolver is constructed with an explicit allow-list of abilities. A model may only call
  # an ability that was named at construction time — this is the guard that stops a model
  # invoking arbitrary abilities (the legacy's stated reason, resolver.php:19-22). It reads
  # abilities from a Registry passed in explicitly; there is no ambient global registry
  # (Non-negotiable 1).
  #
  # Function-name encoding is reproduced verbatim: "tec/create_event" <-> "wpab__tec__create_event"
  # (resolver.php:213-230).
  class FunctionResolver
    ABILITY_PREFIX = "wpab__" # resolver.php:33

    def initialize(registry, allowed:)
      @registry = registry
      @allowed = Array(allowed).map { |a| a.respond_to?(:name) ? a.name : a.to_s }.to_set
    end

    # resolver.php:213
    def self.ability_name_to_function_name(ability_name)
      ABILITY_PREFIX + ability_name.gsub("/", "__")
    end

    # resolver.php:227
    def self.function_name_to_ability_name(function_name)
      function_name.delete_prefix(ABILITY_PREFIX).gsub("__", "/")
    end

    # resolver.php:72
    def ability_call?(function_name)
      function_name.is_a?(String) && function_name.start_with?(ABILITY_PREFIX)
    end

    # Reproduces execute_ability() (resolver.php:93): resolve the function name to an ability,
    # enforce the allow-list, look it up, and run its pipeline. Returns a Result — an error
    # Result carries the same codes the legacy FunctionResponse does (invalid_ability_call,
    # ability_not_allowed, ability_not_found), and a success Result carries the ability's output.
    def execute(function_name, args = nil)
      unless ability_call?(function_name)
        return Result.error("invalid_ability_call", "Not an ability function call")
      end

      ability_name = self.class.function_name_to_ability_name(function_name)

      unless @allowed.include?(ability_name)
        return Result.error(
          "ability_not_allowed",
          %(Ability "#{ability_name}" was not specified in the allowed abilities list.)
        )
      end

      ability = @registry.get(ability_name)
      unless ability
        return Result.error("ability_not_found", %(Ability "#{ability_name}" not found))
      end

      ability.execute(args.nil? || (args.respond_to?(:empty?) && args.empty?) ? nil : args)
    end
  end
end
