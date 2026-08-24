# frozen_string_literal: true

module Composition
  # `resolve_pattern_blocks()`, wp-includes/blocks.php — the pass
  # WP_REST_Templates_Controller runs over a template before serving it:
  #
  #   "Resolve pattern blocks so they don't need to be resolved client-side in the
  #    editor, improving performance." (class-wp-rest-templates-controller.php:684)
  #
  # ⚠️ This is not decoration. Six of twentytwentyfive's eight templates and five of its
  # seven parts are little more than a `<!-- wp:pattern {"slug":…} /-->` reference, so a
  # `/wp/v2/templates` response WITHOUT this pass hands the editor a canvas of unresolved
  # placeholders — the template shows as one empty block instead of its content. The
  # oracle's `templates[home].content.raw` is 3.4 KB of expanded markup where the file on
  # disk is 300 bytes; that difference is entirely this function.
  #
  # AD-01: the pattern REGISTRY it reads is the `patterns` table (loaded by
  # `rake theme:load` from the oracle's registry dump), not a runtime registration hook.
  #
  # One instance per response, so the registry lookups are memoised for exactly as long as
  # they are certainly valid — a `theme:load` between two requests must be seen.
  class PatternResolver
    def self.resolve_content(markup) = new.resolve_content(markup)

    def initialize
      @registry = {}
    end

    # The three lines of the REST controller (:688-690): parse, resolve, serialize.
    def resolve_content(markup)
      Serializer.serialize(resolve(Parser.parse(markup.to_s)))
    end

    # @param blocks [Array<Parser::Block>] a parsed tree, MUTATED in place as the legacy's is
    # @return [Array<Parser::Block>]
    def resolve(blocks, inner_content: nil, seen: Set.new)
      index = 0
      while index < blocks.length
        block = blocks[index]
        if block.block_name == "core/pattern"
          index = expand(blocks, index, inner_content, seen)
        else
          if block.inner_blocks.present?
            block.inner_blocks = resolve(block.inner_blocks, inner_content: block.inner_content, seen: seen)
          end
          index += 1
        end
      end
      blocks
    end

    private

    # One `core/pattern` node. Returns the index to continue from.
    def expand(blocks, index, inner_content, seen)
      attrs = blocks[index].attrs
      slug = attrs.is_a?(Hash) ? attrs["slug"].to_s : ""
      return index + 1 if slug.empty?

      # "Skip recursive patterns" — the reference is DROPPED, not left in place.
      if seen.include?(slug)
        blocks.delete_at(index)
        return index
      end

      pattern = registry(slug)
      return index + 1 if pattern.nil? # "Skip unknown patterns."

      inserted = Parser.parse(pattern.content.to_s.strip)
      stamp_metadata(inserted, slug, pattern) if inserted.length == 1

      seen << slug
      inserted = resolve(inserted, inner_content: nil, seen: seen)
      seen.delete(slug)

      blocks[index, 1] = inserted

      # "If we have inner content, we need to insert nulls in the inner content array,
      # otherwise serialize_blocks will skip blocks." The nil markers in a parent's
      # `inner_content` are positional stand-ins for its children, so replacing one child
      # with N children means replacing one marker with N.
      if inner_content
        markers = inner_content.each_index.select { |i| inner_content[i].nil? }
        at = markers[index]
        inner_content[at, 1] = Array.new(inserted.length, nil) unless at.nil?
      end

      index + inserted.length
    end

    # "For single-root patterns, add the pattern name to make this a pattern instance in
    # the editor." The pattern's own title/description/categories win; whatever the block
    # already carried survives as the fallback, and any other metadata key is untouched.
    METADATA_FIELDS = { "name" => :title, "description" => :description,
                        "categories" => :categories }.freeze

    def stamp_metadata(inserted, slug, pattern)
      block = inserted[0]
      attrs = block.attrs.is_a?(Hash) ? block.attrs.dup : {}
      metadata = attrs["metadata"].is_a?(Hash) ? attrs["metadata"].dup : {}
      metadata["patternName"] = slug

      METADATA_FIELDS.each do |key, field|
        value = pattern.public_send(field)
        value = metadata[key] if blank_value?(value)
        next if blank_value?(value)

        metadata[key] = value.is_a?(Array) ? value.map { |v| sanitize_text(v) } : sanitize_text(value)
      end

      attrs["metadata"] = metadata
      block.attrs = attrs
    end

    # PHP's `if ( $value )`: null, '' and [] are falsy. ('0' is too, but no pattern title
    # is the string zero.)
    def blank_value?(value) = value.nil? || value == "" || value == []

    # sanitize_text_field() reduced to the arms a REGISTRY-sourced string can reach: these
    # values came out of `WP_Block_Patterns_Registry` (via `rake theme:generate`), already
    # tag-free and already translated, so what remains observable is the whitespace
    # collapse. The full port lives in Discussion::FieldFilters#sanitize_text_field and is
    # not reached across the pack boundary for a value that cannot need it.
    def sanitize_text(value) = value.to_s.gsub(/[\r\n\t ]+/, " ").strip

    def registry(slug)
      return @registry[slug] if @registry.key?(slug)

      @registry[slug] = Pattern.find_by(slug: slug)
    end
  end
end
