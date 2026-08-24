# frozen_string_literal: true

module Assistance
  # The abilities + categories registry. Reproduces WP_Abilities_Registry and
  # WP_Ability_Categories_Registry (wp-includes/abilities-api/*).
  #
  # DEVIATION — no process global (Non-negotiable 1, implication 1). The legacy registries are
  # `get_instance()` singletons holding mutable global state that every request shares. Here
  # Registry is an ordinary instantiable object: an application builds one at configuration time
  # and freezes the set of abilities it exposes; a spec builds its own in isolation. There is no
  # `Assistance.registry` process global, so no per-request mutation of shared state and nothing
  # for two tenants to leak across. This is exactly the "per-request/per-tenant context travels
  # explicitly" rule: whoever needs a registry holds one.
  #
  # Reproduced OBSERVABLE behaviour:
  #   * BR-MIGRATE-269 (BR-AI-01): ability names must match ^[a-z0-9-]+/[a-z0-9-]+$; the
  #     namespace prefix is mandatory (class-wp-abilities-registry.php:86).
  #   * BR-MIGRATE-270 (BR-AI-02): re-registering an existing ability FAILS and returns nil —
  #     there is no silent overwrite. The legacy signals the failure with _doing_it_wrong()
  #     (removed with the hook/debug plumbing) and returns null; we reproduce the nil return and
  #     the no-overwrite guarantee (class-wp-abilities-registry.php:97).
  #   * BR-MIGRATE-271 (BR-AI-03): an ability's category must already be registered before the
  #     ability can be (class-wp-abilities-registry.php:110).
  class Registry
    def initialize
      @abilities = {}
      @categories = {}
    end

    # Reproduces WP_Ability_Categories_Registry::register(). Returns the Category, or nil on
    # failure (duplicate slug, invalid slug, invalid properties). The legacy checks the duplicate
    # BEFORE the slug pattern (class-wp-ability-categories-registry.php:58,68); order preserved.
    def register_category(slug, label: nil, description: nil, meta: {})
      return nil if @categories.key?(slug)
      return nil unless slug.is_a?(String) && slug.match?(Category::SLUG_PATTERN)

      category = Category.new(slug, label: label, description: description, meta: meta || {})
      @categories[slug] = category
      category
    rescue Category::InvalidArgument
      nil
    end

    def category_registered?(slug)
      @categories.key?(slug)
    end

    def categories
      @categories.values
    end

    # Reproduces WP_Abilities_Registry::register(). Returns the Ability, or nil on failure.
    # The legacy order is: name pattern -> already-registered -> category-exists -> construct
    # (class-wp-abilities-registry.php:86,97,110). Order preserved so the same input fails at the
    # same gate.
    def register(name, category:, **args)
      return nil unless name.is_a?(String) && name.match?(Ability::NAME_PATTERN)
      return nil if @abilities.key?(name)              # BR-270: no silent overwrite
      return nil unless @categories.key?(category)     # BR-271: category first

      ability = Ability.new(name, category: category, **args)
      @abilities[name] = ability
      ability
    rescue Ability::InvalidArgument
      nil
    end

    # Reproduces WP_Abilities_Registry::unregister(): returns the removed ability, or nil if it
    # was not registered.
    def unregister(name)
      @abilities.delete(name)
    end

    def registered?(name)
      @abilities.key?(name)
    end

    def get(name)
      @abilities[name]
    end

    # WP_Abilities_Registry::get_all_registered().
    def all
      @abilities.values
    end
  end
end
