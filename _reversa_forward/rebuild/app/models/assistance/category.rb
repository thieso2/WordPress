# frozen_string_literal: true

module Assistance
  # An ability category. Reproduces WP_Ability_Category (class-wp-ability-category.php):
  # a slug plus a required human-readable label and description. Categories exist so that
  # BR-MIGRATE-271 can hold — an ability may only name a category that is already registered.
  #
  # The legacy gates category registration on the `wp_abilities_api_categories_init` action
  # (abilities-api.php:645). That timing gate is the hook system (AD-01), which is gone: here a
  # category is registered by a direct method call at configuration time, and the observable
  # rule that survives — "the category must exist before the ability" — is enforced by the
  # registry, not by an action ordering.
  class Category
    # class-wp-ability-categories-registry.php:68
    SLUG_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

    attr_reader :slug, :label, :description, :meta

    class InvalidArgument < StandardError; end

    def initialize(slug, label:, description:, meta: {})
      raise InvalidArgument, "The ability category slug cannot be empty." if slug.to_s.empty?
      raise InvalidArgument, "The ability category properties must contain a `label` string." unless label.is_a?(String) && !label.empty?
      raise InvalidArgument, "The ability category properties must contain a `description` string." unless description.is_a?(String) && !description.empty?

      @slug = slug
      @label = label
      @description = description
      @meta = meta || {}
      freeze
    end
  end
end
