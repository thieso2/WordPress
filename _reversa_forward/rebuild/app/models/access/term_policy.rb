# frozen_string_literal: true

module Access
  # The `edit_term` / `delete_term` / `assign_term` arms, wp-includes/capabilities.php
  # :708-749, plus the taxonomy capability families they resolve through (:751-760).
  #
  # Both built-in taxonomies map the same way -- `category` through manage_categories /
  # edit_categories / delete_categories / assign_categories, `post_tag` through
  # manage_post_tags / edit_post_tags / delete_post_tags / assign_post_tags -- and the
  # second set collapses onto the first at :751-760. A custom taxonomy gets
  # get_taxonomy_capabilities()' defaults, which are the same primitives again.
  class TermPolicy < BasePolicy
    def required_capabilities(action)
      case action.to_sym
      when :create       then ["manage_categories"]      # `$tax->cap->edit_terms`
      when :edit         then term_scoped("manage_categories")
      when :delete       then delete_term
      when :assign       then term_scoped("edit_posts")  # :758-760
      else []
      end
    end

    private

    def term_scoped(primitive)
      return [DO_NOT_ALLOW] if record.nil? || record.taxonomy.nil?   # :722, :732

      [primitive]
    end

    # :738-744: the taxonomy's default term can never be deleted. Both the legacy
    # spelling (`default_category`) and the generic one (`default_term_<taxonomy>`)
    # are consulted, exactly as the arm does.
    def delete_term
      return [DO_NOT_ALLOW] if record.nil? || record.taxonomy.nil?

      taxonomy = record.taxonomy.name
      if record.id == setting_id("default_#{taxonomy}") || record.id == setting_id("default_term_#{taxonomy}")
        return [DO_NOT_ALLOW]
      end

      ["manage_categories"]
    end
  end
end
