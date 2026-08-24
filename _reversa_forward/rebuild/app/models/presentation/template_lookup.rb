# frozen_string_literal: true

module Presentation
  # `get_template_hierarchy()`, wp-includes/block-template-utils.php — the hierarchy of a
  # SLUG, which is a different question from the hierarchy of a REQUEST.
  #
  # ⚠️ Read that distinction before assuming this duplicates TemplateResolver. That class
  # answers "this URL is a category archive whose term is `news`; which template renders
  # it?" — seventeen conditional tags in a fixed order, each with its own candidate list
  # (wp-includes/template.php). THIS answers "somebody named the slug `category-news`;
  # what does it fall back to?" — a pure string decomposition with no query behind it.
  # The legacy keeps both, for the same reason: `/wp/v2/templates/lookup` is asked by an
  # editor that has a slug and no WP_Query.
  #
  # What is NOT duplicated is the RESOLUTION step. Turning a candidate list into the one
  # winning row — scoped to the active theme, first match wins — is TemplateResolver's
  # `first_match`, and it is reused rather than rewritten, so the template the editor
  # opens is by construction the template the front end renders.
  class TemplateLookup
    # :810 — the prefixes whose slug is `<type>-<something>` and which therefore fall back
    # to their bare type.
    SIMPLE_PREFIXES = /\A(author|category|archive|tag|page)-.+\z/
    # :816 — `taxonomy-<taxonomy>[-<term>]` and `single-<post_type>[-<slug>]`, which need
    # the registered vocabularies to know where the type name ends.
    QUALIFIED_PREFIXES = /\A(taxonomy|single)-(.+)\z/

    # `get_post_types()` / `get_taxonomies()` — the vocabularies :816-845 needs in order to
    # know where a type name ends inside `single-<post_type>-<slug>`.
    #
    # ⚠️ Stated here, in REGISTRATION ORDER, rather than read from PublicApi::SchemaRegistry.
    # That module is the same list, but it belongs to a DELIVERY SURFACE, and PublicApi
    # already reaches into Presentation (PublicApi::TemplateSerializer). Reading it back
    # would close a namespace cycle — the one thing bin/check_cycles exists to refuse
    # (topology_decision.md option 3). AD-01 makes the list final in either place: there
    # is no `register_post_type` hook for a plugin to extend it through.
    POST_TYPES = %w[
      post page attachment nav_menu_item wp_block wp_template wp_template_part
      wp_navigation wp_global_styles wp_font_family wp_font_face
    ].freeze

    TAXONOMIES = %w[
      category post_tag nav_menu link_category post_format wp_theme
      wp_template_part_area wp_pattern_category
    ].freeze

    def initialize(theme_slug: nil)
      @resolver = TemplateResolver.new(theme_slug: theme_slug)
    end

    # WP_REST_Templates_Controller::get_template_fallback() (:160): walk the hierarchy,
    # shifting off the front until a candidate with CONTENT is found. Because `first_match`
    # already returns the first hierarchy entry that exists, the loop collapses to one
    # call plus a skip over empty-content rows — the `while ! empty( $hierarchy ) &&
    # empty( $fallback_template->content )` condition, stated directly.
    #
    # @return [Composition::Template, nil] nil is the legacy's empty object, not a 404.
    def resolve(slug, is_custom: false, template_prefix: nil)
      hierarchy(slug, is_custom: is_custom, template_prefix: template_prefix).each do |candidate|
        template = @resolver.send(:first_match, [candidate])
        return template if template && template.content.to_s.strip.present?
      end
      nil
    end

    # get_template_hierarchy( $slug, $is_custom, $template_prefix ), transcribed.
    def hierarchy(slug, is_custom: false, template_prefix: nil)
      slug = slug.to_s
      return ["index"] if slug == "index"
      return %w[page singular index] if is_custom
      return %w[front-page home index] if slug == "front-page"

      list = [slug]
      prefix = template_prefix.to_s
      if prefix.present?
        type = prefix.split("-").first.to_s
        list << prefix unless [slug, type].include?(prefix)
        list << type unless slug == type
      elsif (match = SIMPLE_PREFIXES.match(slug))
        list << match[1]
      elsif (match = QUALIFIED_PREFIXES.match(slug))
        list.concat(qualified_fallbacks(match[1], match[2]))
      end

      # :846-869 — the three unconditional tails, in the legacy's order.
      list << "archive" if slug.start_with?("author", "taxonomy", "category", "tag") || slug == "date"
      list << "single" if slug == "attachment"
      list << "singular" if slug.start_with?("single", "page") || slug == "attachment"
      list << "index"
      list.uniq
    end

    private

    # :816-845. `single-<post_type>` and `taxonomy-<taxonomy>` collapse to the bare type;
    # `single-<post_type>-<slug>` keeps the qualified form first. The vocabularies are the
    # rebuild's declared ones (PublicApi::SchemaRegistry, DEV-002) rather than a registry
    # a plugin could extend — AD-01.
    def qualified_fallbacks(type, remaining)
      items = type == "single" ? POST_TYPES : TAXONOMIES
      items.each do |item|
        next unless remaining.start_with?(item)
        return [type] if remaining == item
        return ["#{type}-#{item}", type] if remaining.length > item.length + 1
      end
      []
    end
  end
end
