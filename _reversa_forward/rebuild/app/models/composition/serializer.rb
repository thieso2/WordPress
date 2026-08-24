# frozen_string_literal: true

module Composition
  # The exact inverse of Composition::Parser. Ports wp-includes/blocks.php:
  #   serialize_blocks(), serialize_block(), get_comment_delimited_block_content(),
  #   serialize_block_attributes(), strip_core_block_namespace().
  #
  # Serialization walks `inner_content` — the interleaving of literal HTML chunks and nil
  # markers standing where an inner block belongs — substituting each nil with the
  # serialized inner block, in order. Because the Parser preserves that interleaving,
  # serialize(parse(markup)) reproduces the original bytes for content the editor did not
  # touch, and the editor's own output round-trips through the same grammar the Wave 3
  # differential specs already verified against the live oracle.
  #
  # Input is either a Parser::Block tree (Struct) or the plain-Hash tree the editor API
  # exchanges with the React island (keys: "blockName"/"name", "attrs", "innerBlocks",
  # "innerHTML", "innerContent"). Both are accepted so the same code serializes on save.
  module Serializer
    module_function

    # serialize_blocks(): the aggregate serialization of a list of top-level blocks.
    def serialize(blocks)
      Array(blocks).map { |block| serialize_block(block) }.join
    end

    # serialize_block(): rebuild one node's content by interleaving innerContent chunks
    # with its serialized inner blocks, then wrap in comment delimiters.
    def serialize_block(block)
      name = block_name(block)
      attrs = block_attrs(block)
      inner_blocks = block_inner_blocks(block)
      inner_content = block_inner_content(block)

      # WP_Block_Parser_Block always carries innerContent; when a caller (the editor) omits
      # it, fall back to innerHTML followed by the inner blocks — the shape a freshly
      # inserted block has before it has ever been parsed.
      content =
        if inner_content.nil?
          block_inner_html(block).to_s + inner_blocks.map { |b| serialize_block(b) }.join
        else
          index = 0
          inner_content.map do |chunk|
            if chunk.nil?
              serialized = serialize_block(inner_blocks[index])
              index += 1
              serialized
            else
              chunk
            end
          end.join
        end

      comment_delimited_block_content(name, attrs, content)
    end

    # get_comment_delimited_block_content(): a nil block name (freeform/classic) is raw
    # content; empty content collapses to the void form `<!-- wp:name /-->`.
    def comment_delimited_block_content(block_name, block_attributes, block_content)
      return block_content if block_name.nil?

      serialized_name = strip_core_block_namespace(block_name)
      serialized_attrs = block_attributes.nil? || block_attributes.empty? ? "" : "#{serialize_block_attributes(block_attributes)} "

      if block_content.nil? || block_content.empty?
        "<!-- wp:#{serialized_name} #{serialized_attrs}/-->"
      else
        "<!-- wp:#{serialized_name} #{serialized_attrs}-->#{block_content}<!-- /wp:#{serialized_name} -->"
      end
    end

    # serialize_block_attributes(): JSON with unescaped slashes + unicode, then the fixed
    # strtr table that keeps the delimiter comment un-terminable and HTML-safe. Order
    # matters: the backslash rule runs first, exactly as PHP's strtr picks the longest key.
    def serialize_block_attributes(block_attributes)
      encoded = json_encode(block_attributes)
      encoded.gsub(/\\\\|--|<|>|&|\\"/) do |m|
        case m
        when "\\\\" then "\\u005c"
        when "--"   then "\\u002d\\u002d"
        when "<"    then "\\u003c"
        when ">"    then "\\u003e"
        when "&"    then "\\u0026"
        when "\\\"" then "\\u0022"
        end
      end
    end

    # strip_core_block_namespace(): drop the implicit "core/" prefix for serialization.
    def strip_core_block_namespace(block_name)
      block_name.is_a?(String) && block_name.start_with?("core/") ? block_name[5..] : block_name
    end

    # wp_json_encode( $data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE ). Ruby's
    # JSON already leaves slashes and unicode unescaped and uses PHP-compatible separators
    # (no spaces), so a plain generate matches the byte layout the delimiter carries.
    def json_encode(data)
      JSON.generate(data)
    end

    # ── tolerant accessors: Parser::Block struct OR editor Hash (string/symbol keys) ──
    def block_name(b)
      return b.block_name if b.respond_to?(:block_name)
      fetch(b, "blockName", "name")
    end

    def block_attrs(b)
      return b.attrs if b.respond_to?(:attrs)
      fetch(b, "attrs") || {}
    end

    def block_inner_blocks(b)
      return b.inner_blocks || [] if b.respond_to?(:inner_blocks)
      fetch(b, "innerBlocks") || []
    end

    def block_inner_html(b)
      return b.inner_html if b.respond_to?(:inner_html)
      fetch(b, "innerHTML") || ""
    end

    def block_inner_content(b)
      return b.inner_content if b.respond_to?(:inner_content)
      # A Hash from the editor may legitimately omit innerContent (freshly inserted block);
      # distinguish "absent" (nil → fall back to innerHTML) from "present but empty" ([]).
      b.key?("innerContent") ? b["innerContent"] : (b.key?(:innerContent) ? b[:innerContent] : nil)
    end

    def fetch(hash, *keys)
      keys.each do |k|
        return hash[k] if hash.key?(k)
        return hash[k.to_sym] if hash.key?(k.to_sym)
      end
      nil
    end
  end
end
