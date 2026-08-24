# frozen_string_literal: true

module Composition
  # BR-MIGRATE-182..193. Port of WP_Block_Parser (wp-includes/class-wp-block-parser.php).
  #
  # The block delimiter syntax is an HTML comment carrying a name and an optional JSON
  # attribute object:
  #
  #     <!-- wp:paragraph {"dropCap":true} -->  <p>…</p>  <!-- /wp:paragraph -->
  #     <!-- wp:template-part {"slug":"header"} /-->        (void)
  #
  # Everything between blocks is "freeform" and is preserved as a block with a nil name.
  # That is load-bearing: it is how the parser round-trips content it does not understand,
  # and dropping it would silently delete classic-editor content.
  #
  # ── PCRE vs Onigmo (RISK-005 applies here too) ────────────────────────────────────
  # The legacy tokenizer is one regex, at class-wp-block-parser.php:247. Three
  # translations, each deliberate:
  #
  #  1. `/s` in PCRE is DOTALL. Ruby spells that `/m`. Ruby's own `/m` is not PCRE's `/m`,
  #     and getting this backwards makes the attribute object stop matching at a newline —
  #     which is exactly what a pretty-printed template contains.
  #  2. `*+` is a POSSESSIVE quantifier. Onigmo supports it with the same meaning, so it is
  #     carried over verbatim rather than rewritten to a greedy form. Rewriting it would
  #     change the backtracking behaviour on a malformed attribute object from "fail fast"
  #     to "explore every split", which is a denial-of-service shape on hostile input.
  #  3. There are no `^`/`$` anchors in this pattern, so the line-anchor trap that bites
  #     KSES does not apply. Checked rather than assumed.
  class Parser
    # Verbatim from class-wp-block-parser.php:247, with /s -> /m. Built from a
    # single-quoted heredoc so the pattern is byte-for-byte the legacy's: a %r{} literal
    # would need every `}` escaped, and an escaped copy is no longer a copy.
    TOKEN = Regexp.new(<<~'RX'.strip, Regexp::MULTILINE)
      <!--\s+(?<closer>/)?wp:(?<namespace>[a-z][a-z0-9_-]*/)?(?<name>[a-z][a-z0-9_-]*)\s+(?<attrs>\{(?:(?:[^}]+|\}+(?=\})|(?!\}\s+/?-->).)*+)?\}\s+)?(?<void>/)?-->
    RX

    # A parsed node. Mirrors WP_Block_Parser_Block: `inner_html` is the concatenation of
    # the literal chunks, and `inner_content` interleaves those chunks with nil markers
    # standing where an inner block belongs. Serialization depends on that interleaving,
    # so both are kept rather than derived.
    Block = Struct.new(:block_name, :attrs, :inner_blocks, :inner_html, :inner_content,
                       keyword_init: true) do
      def freeform? = block_name.nil?
      def core? = block_name.to_s.start_with?("core/")
      def short_name = block_name.to_s.sub(%r{\Acore/}, "")
    end

    Frame = Struct.new(:block, :token_start, :token_length, :prev_offset, :leading_html_start,
                       keyword_init: true)

    def self.parse(document) = new(document).parse

    def initialize(document)
      @document = document.to_s
      @offset = 0
      @output = []
      @stack = []
    end

    def parse
      proceed until @stack.empty? && @offset >= @document.length && !@pending
      @output
    end

    private

    # Mirrors WP_Block_Parser::proceed()'s state machine rather than reorganising it: the
    # legacy's branch names are preserved so the two can be read side by side.
    def proceed
      token = next_token
      kind, block_name, attrs, start_offset, token_length = token
      stack_depth = @stack.length
      leading_html_start = start_offset > @offset ? @offset : nil

      case kind
      when :no_more_tokens
        if stack_depth.zero?
          add_freeform
        else
          # An unclosed block: everything it opened becomes freeform, exactly as the
          # legacy does. Content is never discarded for being malformed.
          until @stack.empty?
            frame = @stack.pop
            add_block_from_stack(frame)
          end
        end
        @pending = false
        @offset = @document.length

      when :void_block
        if stack_depth.zero?
          add_freeform(leading_html_start ? start_offset - @offset : nil) if leading_html_start
          @output << Block.new(block_name: block_name, attrs: attrs, inner_blocks: [],
                               inner_html: "", inner_content: [])
        else
          parent = @stack.last
          parent.block.inner_blocks << Block.new(block_name: block_name, attrs: attrs,
                                                 inner_blocks: [], inner_html: "",
                                                 inner_content: [])
          add_inner_html(parent, start_offset)
          parent.block.inner_content << nil
          parent.prev_offset = start_offset + token_length
        end
        @offset = start_offset + token_length

      when :block_opener
        @stack << Frame.new(
          block: Block.new(block_name: block_name, attrs: attrs, inner_blocks: [],
                           inner_html: "", inner_content: []),
          token_start: start_offset, token_length: token_length,
          prev_offset: start_offset + token_length, leading_html_start: leading_html_start
        )
        @offset = start_offset + token_length

      when :block_closer
        if stack_depth.zero?
          # A closer with nothing open is text, not an error.
          add_freeform
          @offset = start_offset + token_length
          return
        end
        frame = @stack.pop
        add_inner_html(frame, start_offset)
        frame.block.inner_content.compact! if false # keep nils: they mark inner-block slots
        if @stack.empty?
          if frame.leading_html_start
            @output << freeform(@document[frame.leading_html_start...frame.token_start].to_s)
          end
          @output << frame.block
        else
          parent = @stack.last
          parent.block.inner_blocks << frame.block
          add_inner_html(parent, frame.token_start)
          parent.block.inner_content << nil
          parent.prev_offset = start_offset + token_length
        end
        @offset = start_offset + token_length
      end
    end

    def add_inner_html(frame, upto)
      html = @document[frame.prev_offset...upto].to_s
      return if html.empty?

      frame.block.inner_html += html
      frame.block.inner_content << html
    end

    def add_block_from_stack(frame)
      add_inner_html(frame, @document.length)
      if @stack.empty?
        @output << freeform(@document[frame.leading_html_start...frame.token_start].to_s) if frame.leading_html_start
        @output << frame.block
      else
        parent = @stack.last
        parent.block.inner_blocks << frame.block
        parent.block.inner_content << nil
      end
    end

    # class-wp-block-parser.php:311 — attrs is `array()`, i.e. an empty map, not null.
    # Same distinction as in next_token: PHP renders it `[]` but means `{}`.
    def freeform(html)
      Block.new(block_name: nil, attrs: {}, inner_blocks: [], inner_html: html,
                inner_content: [html])
    end

    def add_freeform(length = nil)
      html = length ? @document[@offset, length].to_s : @document[@offset..].to_s
      return if html.empty?

      @output << freeform(html)
    end

    def next_token
      match = TOKEN.match(@document, @offset)
      return [:no_more_tokens, nil, nil, @document.length, 0] if match.nil?

      started_at = match.begin(0)
      length = match[0].length
      closer = !match[:closer].nil?
      void = !match[:void].nil?
      namespace = match[:namespace] || "core/"
      name = namespace + match[:name]

      # Two distinct "no attributes" cases, and the legacy distinguishes them:
      #
      #  * ABSENT  -> an empty map. class-wp-block-parser.php:279 uses `array()`, and the
      #    source carries a comment about it: "Fun fact! It's not trivial in PHP to create
      #    an empty associative array ... If we use array() we get a JSON []". So PHP
      #    *serialises* it as `[]` while *meaning* `{}`. Ruby has no such ambiguity and
      #    stores `{}` — the same family of hazard as T-02's contiguous-integer-key rule.
      #  * MALFORMED -> nil. json_decode() returns null and the legacy keeps the block
      #    anyway. Raising here would lose the whole document to one bad attribute object.
      attrs = if match[:attrs]
                begin
                  JSON.parse(match[:attrs])
                rescue JSON::ParserError
                  nil
                end
              else
                {}
              end

      # "</wp:name /-->" is nonsense; the legacy treats a closer-with-void as a closer.
      # A closer carries no attributes even when the markup supplies some (:287).
      return [:block_closer, name, nil, started_at, length] if closer
      return [:void_block, name, attrs, started_at, length] if void

      [:block_opener, name, attrs, started_at, length]
    end
  end
end
