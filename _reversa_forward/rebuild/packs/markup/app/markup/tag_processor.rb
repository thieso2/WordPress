# frozen_string_literal: true

module Markup
  # A forward-only, byte-level scanner over an HTML document.
  #
  # BR-MIGRATE-220 — this class never constructs a tree. It walks the source once,
  # recording byte offsets for the token it is sitting on, and every modification
  # (`set_attribute`, `remove_attribute`, `add_class`, `remove_class`,
  # `set_modifiable_text`) is queued as a byte splice and applied only when
  # `get_updated_html` is called. Everything the document does not mention is left
  # untouched, byte for byte.
  #
  # BR-MIGRATE-221 — scanning is forward-only. There is no `previous_tag`. The only way
  # to revisit a position is to name it with `set_bookmark` and return to it with `seek`,
  # and bookmarks are shifted as splices are applied so that they keep pointing at the
  # same token rather than the same offset.
  #
  # Legacy: wp-includes/html-api/class-wp-html-tag-processor.php:4913 (BR-MIGRATE-220),
  # :1360 (BR-MIGRATE-221), :2971 (BR-MIGRATE-222).
  class TagProcessor # rubocop:disable Metrics/ClassLength
    # Legacy: class-wp-html-tag-processor.php:421.
    MAX_BOOKMARKS = 10
    # Legacy: class-wp-html-tag-processor.php:432.
    MAX_SEEK_OPS = 1000

    ADD_CLASS = true
    REMOVE_CLASS = false

    # Parser states. Values are preserved verbatim from the legacy constants.
    STATE_READY = "STATE_READY"
    STATE_COMPLETE = "STATE_COMPLETE"
    STATE_INCOMPLETE_INPUT = "STATE_INCOMPLETE_INPUT"
    STATE_MATCHED_TAG = "STATE_MATCHED_TAG"
    STATE_TEXT_NODE = "STATE_TEXT_NODE"
    STATE_CDATA_NODE = "STATE_CDATA_NODE"
    STATE_COMMENT = "STATE_COMMENT"
    STATE_DOCTYPE = "STATE_DOCTYPE"
    STATE_PRESUMPTUOUS_TAG = "STATE_PRESUMPTUOUS_TAG"
    STATE_FUNKY_COMMENT = "STATE_WP_FUNKY"
    STATE_PROCESSING_INSTRUCTION = "STATE_PROCESSING_INSTRUCTION"

    COMMENT_AS_ABRUPTLY_CLOSED_COMMENT = "COMMENT_AS_ABRUPTLY_CLOSED_COMMENT"
    COMMENT_AS_CDATA_LOOKALIKE = "COMMENT_AS_CDATA_LOOKALIKE"
    COMMENT_AS_HTML_COMMENT = "COMMENT_AS_HTML_COMMENT"
    COMMENT_AS_PI_NODE_LOOKALIKE = "COMMENT_AS_PI_NODE_LOOKALIKE"
    COMMENT_AS_INVALID_HTML = "COMMENT_AS_INVALID_HTML"

    NO_QUIRKS_MODE = "no-quirks-mode"
    QUIRKS_MODE = "quirks-mode"

    TEXT_IS_GENERIC = "TEXT_IS_GENERIC"
    TEXT_IS_NULL_SEQUENCE = "TEXT_IS_NULL_SEQUENCE"
    TEXT_IS_WHITESPACE = "TEXT_IS_WHITESPACE"

    WHITESPACE = " \t\f\r\n"
    ASCII_ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    TAG_OPEN_FOLLOWERS = "!/?abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    PI_TARGET_TAIL = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"

    # Escaping applied to attribute values and to text-node replacements.
    # Legacy: class-wp-html-tag-processor.php:4646 and :3971.
    ATTRIBUTE_ESCAPES = {
      "<" => "&lt;", ">" => "&gt;", "&" => "&amp;", '"' => "&quot;", "'" => "&apos;"
    }.freeze

    # Elements whose contents are RAWTEXT/RCDATA and are therefore consumed whole.
    # Legacy: class-wp-html-tag-processor.php:1078.
    RAWTEXT_ELEMENTS = %w[IFRAME NOEMBED NOFRAMES STYLE XMP].freeze
    RCDATA_ELEMENTS = %w[TEXTAREA TITLE].freeze

    # C0 controls, rejected in attribute names.
    # Legacy: class-wp-html-tag-processor.php:4612.
    CONTROL_CHARACTERS = (0..0x1F).map(&:chr).join.b.freeze

    attr_reader :parser_state, :text_node_classification
    attr_accessor :compat_mode

    # Legacy: class-wp-html-tag-processor.php:847.
    def initialize(html)
      @html = html.to_s.b
      @bytes_already_parsed = 0
      @parser_state = STATE_READY
      @token_starts_at = nil
      @token_length = nil
      @tag_name_starts_at = nil
      @tag_name_length = nil
      @text_starts_at = 0
      @text_length = 0
      @is_closing_tag = nil
      @has_self_closing_flag = false
      @attributes = {}
      @duplicate_attributes = nil
      @comment_type = nil
      @text_node_classification = TEXT_IS_GENERIC
      @skip_newline_at = nil
      @bookmarks = {}
      @lexical_updates = {}
      @next_lexical_key = 0
      @classname_updates = {}
      @seek_count = 0
      @parsing_namespace = "html"
      @compat_mode = NO_QUIRKS_MODE
      @last_query = nil
      @sought_tag_name = nil
      @sought_class_name = nil
      @sought_match_offset = 1
      @stop_on_tag_closers = false
    end

    # Switches the tokenizer into a foreign-content namespace.
    #
    # BR-MIGRATE-223 (the HTML Processor drives this from the stack of open elements).
    # Legacy: class-wp-html-tag-processor.php:870.
    def change_parsing_namespace(new_namespace)
      return false unless %w[html math svg].include?(new_namespace)

      @parsing_namespace = new_namespace
      true
    end

    # Advances to the next tag matching `query`, forward-only.
    #
    # `query` is nil (any tag), a tag-name String, or a Hash with `tag_name`,
    # `match_offset`, `class_name`, `tag_closers` keys.
    #
    # BR-MIGRATE-221. Legacy: class-wp-html-tag-processor.php:899.
    def next_tag(query = nil)
      parse_query(query)
      already_found = 0

      loop do
        return false if next_token == false

        if @parser_state == STATE_MATCHED_TAG && matches?
          already_found += 1
        end

        break unless already_found < @sought_match_offset
      end

      true
    end

    # Advances to the next token of any kind — tag, text, comment, DOCTYPE, …
    #
    # BR-MIGRATE-221. Legacy: class-wp-html-tag-processor.php:947.
    def next_token
      base_class_next_token
    end

    # Whether the document ended in the middle of a syntax element.
    #
    # BR-MIGRATE-225 in spirit: an incomplete token is reported, never guessed at.
    # Legacy: class-wp-html-tag-processor.php:1172.
    def paused_at_incomplete_token?
      @parser_state == STATE_INCOMPLETE_INPUT
    end

    # Enumerates the matched tag's class names, decoded and deduplicated.
    #
    # Legacy: class-wp-html-tag-processor.php:1200.
    def class_list
      return to_enum(:class_list) unless block_given?
      return unless @parser_state == STATE_MATCHED_TAG

      class_value = get_attribute("class")
      return unless class_value.is_a?(String)

      class_value = class_value.b
      seen = []
      is_quirks = @compat_mode == QUIRKS_MODE
      at = 0

      while at < class_value.bytesize
        at += ByteScan.span(class_value, WHITESPACE, at)
        return if at >= class_value.bytesize

        length = ByteScan.cspan(class_value, WHITESPACE, at)
        return if length.zero?

        name = class_value.byteslice(at, length)
        name = name.downcase if is_quirks
        at += length

        next if seen.include?(name)

        seen << name
        yield utf8(name)
      end
    end

    # Whether the matched tag carries the given class name.
    #
    # Legacy: class-wp-html-tag-processor.php:1259.
    def has_class?(wanted_class)
      return nil unless @parser_state == STATE_MATCHED_TAG

      case_insensitive = @compat_mode == QUIRKS_MODE
      wanted = wanted_class.b

      class_list.each do |class_name|
        candidate = class_name.b
        next unless candidate.bytesize == wanted.bytesize

        return true if case_insensitive ? candidate.downcase == wanted.downcase : candidate == wanted
      end

      false
    end

    # Names the current token so that `seek` can return to it later.
    #
    # BR-MIGRATE-221 — bookmarks deliberately hide their byte offsets. They are stored as
    # spans and shifted whenever splices are applied, so a bookmark keeps identifying the
    # same token even after the document around it has changed; a bookmark whose entire
    # span is overwritten is released rather than silently pointing at the wrong bytes.
    #
    # Legacy: class-wp-html-tag-processor.php:1360.
    def set_bookmark(name)
      return false if @parser_state == STATE_COMPLETE || @parser_state == STATE_INCOMPLETE_INPUT
      return false if !@bookmarks.key?(name) && @bookmarks.size >= max_bookmarks

      @bookmarks[name] = Span.new(@token_starts_at, @token_length)
      true
    end
    alias base_class_set_bookmark set_bookmark

    # Legacy: class-wp-html-tag-processor.php:1393.
    def release_bookmark(name)
      return false unless @bookmarks.key?(name)

      @bookmarks.delete(name)
      true
    end

    # Legacy: class-wp-html-tag-processor.php:2704.
    def has_bookmark?(bookmark_name)
      @bookmarks.key?(bookmark_name)
    end

    # Moves the cursor back (or forward) to a bookmarked token.
    #
    # BR-MIGRATE-221 — this and `set_bookmark` are the only way to revisit a position.
    # Pending splices are flushed first so that the reparse sees the updated document.
    # The seek budget exists to keep a caller from turning a linear scan quadratic.
    #
    # Legacy: class-wp-html-tag-processor.php:2719.
    def seek(bookmark_name)
      return false unless @bookmarks.key?(bookmark_name)

      existing_bookmark = @bookmarks[bookmark_name]
      return true if @token_starts_at == existing_bookmark.start && @token_length == existing_bookmark.length

      @seek_count += 1
      return false if @seek_count > max_seek_ops

      # Flush out any pending updates to the document.
      get_updated_html

      @bytes_already_parsed = @bookmarks[bookmark_name].start
      @parser_state = STATE_READY
      next_token
    end

    # Value of an attribute on the matched tag: a String, `true` for a boolean
    # attribute, or nil when absent.
    #
    # Legacy: class-wp-html-tag-processor.php:2870.
    def get_attribute(name)
      return nil unless @parser_state == STATE_MATCHED_TAG

      comparable = name.b.downcase

      class_name_updates_to_attributes_updates if comparable == "class"

      enqueued_value = get_enqueued_attribute_value(comparable)
      return enqueued_value == :none ? nil : enqueued_value unless enqueued_value == false

      attribute = @attributes[comparable]
      return nil if attribute.nil?
      return true if attribute.is_true

      utf8(get_decoded_attribute_value(attribute))
    end
    alias base_class_get_attribute get_attribute

    # Lowercased names of every attribute on the matched tag starting with `prefix`.
    #
    # BR-MIGRATE-222 — this is the attribute-discovery primitive. Without a tree there is
    # no `element.attributes` collection to walk, so consumers that need to find "every
    # `data-wp-*` attribute on this element" (the Interactivity API is the reason this
    # exists) ask for them by prefix. Matching is ASCII-case-insensitive because the HTML
    # specification forbids two attributes on one tag whose names differ only in case.
    # Attributes enqueued by `set_attribute` but not yet written are included; attributes
    # enqueued for removal are excluded.
    #
    # Legacy: class-wp-html-tag-processor.php:2971.
    def get_attribute_names_with_prefix(prefix)
      return nil if @parser_state != STATE_MATCHED_TAG || @is_closing_tag

      comparable = prefix.b.downcase

      has_class = @attributes.key?("class")
      if comparable.empty? || "class".start_with?(comparable)
        @classname_updates.each_value do |update|
          if (has_class && update == REMOVE_CLASS) || (!has_class && update == ADD_CLASS)
            class_name_updates_to_attributes_updates
            break
          end
        end
      end

      additions = []
      removals = {}
      @lexical_updates.each do |update_name, update|
        next if update_name.is_a?(Integer) || update_name == "modifiable text"

        if update.text.empty?
          removals[update_name] = true
        elsif !@attributes.key?(update_name) && update_name.start_with?(comparable)
          additions << update_name
        end
      end

      matches = @attributes.keys.select do |attr_name|
        attr_name.start_with?(comparable) && !removals.key?(attr_name)
      end

      (additions.empty? ? matches : additions + matches).map { |name| utf8(name) }
    end

    # Legacy: class-wp-html-tag-processor.php:3029.
    def get_namespace
      @parsing_namespace
    end

    # Uppercase name of the matched tag, or nil when not on one.
    #
    # Legacy: class-wp-html-tag-processor.php:3049.
    def get_tag
      return nil if @tag_name_starts_at.nil?

      tag_name = @html.byteslice(@tag_name_starts_at, @tag_name_length)
                      .gsub("\x00", Decoder::REPLACEMENT_CHARACTER)

      return utf8(tag_name.upcase) if @parser_state == STATE_MATCHED_TAG

      # Processing instruction targets are case-sensitive.
      return utf8(tag_name) if @parser_state == STATE_PROCESSING_INSTRUCTION
      return utf8(tag_name) if @parser_state == STATE_COMMENT &&
                               get_comment_type == COMMENT_AS_PI_NODE_LOOKALIKE

      nil
    end
    alias base_class_get_tag get_tag

    # Legacy: class-wp-html-tag-processor.php:3485.
    def has_self_closing_flag?
      return false unless @parser_state == STATE_MATCHED_TAG

      @has_self_closing_flag
    end
    alias base_class_has_self_closing_flag has_self_closing_flag?

    # Whether the matched tag is a closing tag. `</br>` is reported as an opener because
    # the HTML parser treats it as one.
    #
    # Legacy: class-wp-html-tag-processor.php:3510.
    def tag_closer?
      @parser_state == STATE_MATCHED_TAG && @is_closing_tag && get_tag != "BR"
    end
    alias base_class_tag_closer? tag_closer?

    # One of `#tag`, `#text`, `#cdata-section`, `#comment`, `#doctype`,
    # `#presumptuous-tag`, `#funky-comment`, `#processing-instruction`, or nil.
    #
    # Legacy: class-wp-html-tag-processor.php:3551.
    def get_token_type
      case @parser_state
      when STATE_MATCHED_TAG then "#tag"
      when STATE_DOCTYPE then "#doctype"
      else get_token_name
      end
    end
    alias base_class_get_token_type get_token_type

    # Legacy: class-wp-html-tag-processor.php:3584.
    def get_token_name
      case @parser_state
      when STATE_MATCHED_TAG then get_tag
      when STATE_TEXT_NODE then "#text"
      when STATE_CDATA_NODE then "#cdata-section"
      when STATE_COMMENT then "#comment"
      when STATE_DOCTYPE then "html"
      when STATE_PRESUMPTUOUS_TAG then "#presumptuous-tag"
      when STATE_FUNKY_COMMENT then "#funky-comment"
      when STATE_PROCESSING_INSTRUCTION then "#processing-instruction"
      end
    end
    alias base_class_get_token_name get_token_name

    # Legacy: class-wp-html-tag-processor.php:3633.
    def get_comment_type
      return nil unless @parser_state == STATE_COMMENT

      @comment_type
    end

    # The comment's text as a browser would see it, including the syntax quirks that
    # `get_modifiable_text` cannot expose because changing them would change the node
    # type.
    #
    # Legacy: class-wp-html-tag-processor.php:3659.
    def get_full_comment_text
      return get_modifiable_text if @parser_state == STATE_FUNKY_COMMENT
      return nil unless @parser_state == STATE_COMMENT

      case get_comment_type
      when COMMENT_AS_HTML_COMMENT, COMMENT_AS_ABRUPTLY_CLOSED_COMMENT
        get_modifiable_text
      when COMMENT_AS_CDATA_LOOKALIKE
        "[CDATA[#{get_modifiable_text}]]"
      when COMMENT_AS_PI_NODE_LOOKALIKE
        "?#{get_tag}#{get_modifiable_text}?"
      when COMMENT_AS_INVALID_HTML
        preceding = @html.byteslice(@text_starts_at - 1, 1)
        "#{preceding == '?' ? '?' : ''}#{get_modifiable_text}"
      end
    end

    # Splits a text node so that leading NULL bytes and leading (decoded) whitespace can
    # be classified separately from the rest.
    #
    # BR-MIGRATE-223 depends on this: tree construction treats inter-element whitespace
    # differently from other text in almost every insertion mode.
    #
    # Legacy: class-wp-html-tag-processor.php:3724.
    def subdivide_text_appropriately
      return false unless @parser_state == STATE_TEXT_NODE

      @text_node_classification = TEXT_IS_GENERIC

      # NULL bytes are categorically different from `&#x00;`.
      leading_nulls = ByteScan.span(@html, "\x00", @text_starts_at, @text_length)
      if leading_nulls.positive?
        @token_length = leading_nulls
        @text_length = leading_nulls
        @bytes_already_parsed = @token_starts_at + leading_nulls
        @text_node_classification = TEXT_IS_NULL_SEQUENCE
        return true
      end

      at = @text_starts_at
      stop = @text_starts_at + @text_length
      while at < stop
        at += ByteScan.span(@html, WHITESPACE, at, stop - at)

        if at < stop && @html.getbyte(at) == 0x26 # `&`
          replacement, matched_byte_length = Decoder.read_character_reference("data", @html, at)
          if replacement && ByteScan.span(replacement, WHITESPACE, 0) == 1
            at += matched_byte_length
            next
          end
        end

        break
      end

      if at > @text_starts_at
        new_length = at - @text_starts_at
        @text_length = new_length
        @token_length = new_length
        @bytes_already_parsed = at
        @text_node_classification = TEXT_IS_WHITESPACE
        return true
      end

      false
    end

    # The token's modifiable text: a text node's contents, a comment's inner text, the
    # contents of SCRIPT/STYLE/TEXTAREA/TITLE, and so on.
    #
    # Legacy: class-wp-html-tag-processor.php:3807.
    def get_modifiable_text # rubocop:disable Metrics/AbcSize
      enqueued = @lexical_updates["modifiable text"]
      has_enqueued_update = !enqueued.nil?

      return "" if !has_enqueued_update && (@text_starts_at.nil? || @text_length.zero?)

      text = has_enqueued_update ? enqueued.text.b : @html.byteslice(@text_starts_at, @text_length)

      if has_enqueued_update && @parser_state == STATE_PROCESSING_INSTRUCTION
        lead = ByteScan.span(text, WHITESPACE, 0)
        text = text.byteslice(lead, text.bytesize - lead - 2)
      end

      # Input-stream preprocessing, deferred until now.
      text = text.gsub("\r\n", "\n").gsub("\r", "\n")

      if [STATE_CDATA_NODE, STATE_COMMENT, STATE_DOCTYPE, STATE_FUNKY_COMMENT,
          STATE_PROCESSING_INSTRUCTION].include?(@parser_state)
        return utf8(text.gsub("\x00", Decoder::REPLACEMENT_CHARACTER))
      end

      tag_name = get_token_name
      if tag_name == "SCRIPT" || RAWTEXT_ELEMENTS.include?(tag_name)
        return utf8(text.gsub("\x00", Decoder::REPLACEMENT_CHARACTER))
      end

      decoded = Decoder.decode("data", text)

      # The first line feed after LISTING, PRE and TEXTAREA is an authoring convenience.
      if decoded.byteslice(0, 1) == "\n" &&
         ((@skip_newline_at == @token_starts_at && tag_name == "#text") || tag_name == "TEXTAREA")
        decoded = decoded.byteslice(1, decoded.bytesize - 1)
      end

      if tag_name == "#text" && get_namespace == "html"
        utf8(decoded.gsub("\x00", ""))
      else
        utf8(decoded.gsub("\x00", Decoder::REPLACEMENT_CHARACTER))
      end
    end

    # Replaces the token's modifiable text.
    #
    # BR-MIGRATE-220 — like every other modification this only enqueues a byte splice.
    # Text nodes are escaped, comment and processing-instruction data are not (and are
    # rejected when they would prematurely terminate the token).
    #
    # Legacy: class-wp-html-tag-processor.php:3966.
    def set_modifiable_text(plaintext_content)
      case @parser_state
      when STATE_TEXT_NODE
        @lexical_updates["modifiable text"] = TextReplacement.new(
          @text_starts_at, @text_length, escape_attribute_value(plaintext_content)
        )
        true
      when STATE_COMMENT
        return false unless @comment_type == COMMENT_AS_HTML_COMMENT
        # Reject text that could close the comment.
        return false if /--!?>/n.match?(plaintext_content.b)

        @lexical_updates["modifiable text"] =
          TextReplacement.new(@text_starts_at, @text_length, plaintext_content.b)
        true
      when STATE_PROCESSING_INSTRUCTION
        return false if plaintext_content.include?(">")
        return false unless ByteScan.span(plaintext_content.b, WHITESPACE, 0).zero?

        data_at = @tag_name_starts_at + @tag_name_length
        @lexical_updates["modifiable text"] = TextReplacement.new(
          data_at, @token_starts_at + @token_length - data_at, " #{plaintext_content}?>".b
        )
        true
      else
        false
      end
    end

    # Sets an attribute on the matched tag. `value` may be a String, `true` for a boolean
    # attribute, or `false` to remove it.
    #
    # BR-MIGRATE-220. Legacy: class-wp-html-tag-processor.php:4586.
    def set_attribute(name, value) # rubocop:disable Metrics/AbcSize
      return false if @parser_state != STATE_MATCHED_TAG || @is_closing_tag

      name = name.b
      return false unless valid_attribute_name?(name)

      # > The values "true" and "false" are not allowed on boolean attributes.
      return remove_attribute(name) if value == false

      if value == true
        updated_attribute = name
      else
        # DIVERGENCE (see README): the legacy runs `esc_url()` over the value of a URI
        # attribute (`href`, `src`, `action`, …) before escaping. `esc_url()` lives in the
        # sanitizing pack and topology_decision.md option 3 forbids the dependency, so
        # every attribute takes the plain escaping path here.
        escaped_new_value = escape_attribute_value(value)
        # If escaping wiped out the update, reject it.
        return false if escaped_new_value.empty? && !value.to_s.empty?

        updated_attribute = "#{name}=\"#{escaped_new_value}\"".b
      end

      comparable_name = name.downcase

      existing_attribute = @attributes[comparable_name]
      @lexical_updates[comparable_name] = if existing_attribute
                                            TextReplacement.new(existing_attribute.start,
                                                                existing_attribute.length,
                                                                updated_attribute)
                                          else
                                            TextReplacement.new(@tag_name_starts_at + @tag_name_length,
                                                                0, " #{updated_attribute}".b)
                                          end

      @classname_updates = {} if comparable_name == "class" && !@classname_updates.empty?

      true
    end

    # BR-MIGRATE-220. Legacy: class-wp-html-tag-processor.php:4737.
    def remove_attribute(name)
      return false if @parser_state != STATE_MATCHED_TAG || @is_closing_tag

      name = name.b.downcase

      @classname_updates = {} if name == "class" && !@classname_updates.empty?

      unless @attributes.key?(name)
        @lexical_updates.delete(name)
        return false
      end

      attribute = @attributes[name]
      @lexical_updates[name] = TextReplacement.new(attribute.start, attribute.length, "".b)

      # Remove any duplicated declarations of the same attribute, so they vanish together.
      (@duplicate_attributes&.fetch(name, nil) || []).each do |duplicate|
        enqueue_anonymous_update(TextReplacement.new(duplicate.start, duplicate.length, "".b))
      end

      true
    end

    # BR-MIGRATE-220. Legacy: class-wp-html-tag-processor.php:4815.
    def add_class(class_name)
      enqueue_class_update(class_name, ADD_CLASS)
    end

    # BR-MIGRATE-220. Legacy: class-wp-html-tag-processor.php:4857.
    def remove_class(class_name)
      enqueue_class_update(class_name, REMOVE_CLASS)
    end

    # The document with every enqueued splice applied.
    #
    # BR-MIGRATE-220 — this is the moment the byte-level model becomes visible. Updates
    # are sorted by start offset and spliced in a single pass; the cursor and every
    # bookmark are shifted by the accumulated deltas; and then the current token is
    # reparsed in place so the processor is exactly where it was, looking at the
    # now-updated attributes.
    #
    # Legacy: class-wp-html-tag-processor.php:4913.
    def get_updated_html
      requires_no_updating = @classname_updates.empty? && @lexical_updates.empty?
      return utf8(@html) if requires_no_updating

      before_current_tag = @token_starts_at || 0

      class_name_updates_to_attributes_updates
      before_current_tag += apply_attributes_updates(before_current_tag)

      @bytes_already_parsed = before_current_tag
      base_class_next_token

      utf8(@html)
    end

    def to_s
      get_updated_html
    end

    # Full DOCTYPE details, or nil when not on a DOCTYPE token.
    #
    # Legacy: class-wp-html-tag-processor.php:5073.
    def get_doctype_info
      return nil unless @parser_state == STATE_DOCTYPE

      DoctypeInfo.from_doctype_token(@html.byteslice(@token_starts_at, @token_length))
    end

    protected

    attr_reader :html, :bookmarks, :attributes

    def max_bookmarks
      MAX_BOOKMARKS
    end

    def max_seek_ops
      MAX_SEEK_OPS
    end

    def utf8(bytes)
      return bytes if bytes.nil?

      bytes.dup.force_encoding(Encoding::UTF_8)
    end

    # Legacy: class-wp-html-tag-processor.php:965.
    def base_class_next_token # rubocop:disable Metrics/AbcSize
      was_at = @bytes_already_parsed
      after_tag

      return false if @parser_state == STATE_COMPLETE || @parser_state == STATE_INCOMPLETE_INPUT

      @parser_state = STATE_READY

      if @bytes_already_parsed >= @html.bytesize
        @parser_state = STATE_COMPLETE
        return false
      end

      unless parse_next_tag
        @bytes_already_parsed = was_at if @parser_state == STATE_INCOMPLETE_INPUT
        return false
      end

      unless [STATE_INCOMPLETE_INPUT, STATE_COMPLETE, STATE_MATCHED_TAG].include?(@parser_state)
        return true
      end

      nil while parse_next_attribute

      if @parser_state == STATE_INCOMPLETE_INPUT || @bytes_already_parsed >= @html.bytesize
        @parser_state = STATE_INCOMPLETE_INPUT
        @bytes_already_parsed = was_at
        return false
      end

      tag_ends_at = @html.index(">", @bytes_already_parsed)
      if tag_ends_at.nil?
        @parser_state = STATE_INCOMPLETE_INPUT
        @bytes_already_parsed = was_at
        return false
      end

      @parser_state = STATE_MATCHED_TAG
      @bytes_already_parsed = tag_ends_at + 1
      @token_length = @bytes_already_parsed - @token_starts_at

      if @is_closing_tag || @parsing_namespace != "html" ||
         ByteScan.span(@html, "iIlLnNpPsStTxX", @tag_name_starts_at, 1) != 1
        return true
      end

      tag_name = get_tag

      if tag_name == "LISTING" || tag_name == "PRE"
        @skip_newline_at = @bytes_already_parsed
        return true
      end

      # Preserve the opening-tag pointers; finding the closer overwrites them.
      tag_name_starts_at = @tag_name_starts_at
      tag_name_length = @tag_name_length
      tag_ends_at = @token_starts_at + @token_length
      has_self_closing_flag = @has_self_closing_flag
      # PHP arrays are values, so the legacy's plain assignment snapshots them here;
      # Ruby hashes are references, so the snapshot has to be explicit.
      attributes = @attributes.dup
      duplicate_attributes = @duplicate_attributes&.dup

      found_closer =
        if tag_name == "SCRIPT"
          skip_script_data
        elsif RCDATA_ELEMENTS.include?(tag_name)
          skip_rcdata(tag_name)
        elsif RAWTEXT_ELEMENTS.include?(tag_name)
          skip_rawtext(tag_name)
        else
          return true
        end

      unless found_closer
        @parser_state = STATE_INCOMPLETE_INPUT
        @bytes_already_parsed = was_at
        return false
      end

      @token_starts_at = was_at
      @token_length = @bytes_already_parsed - @token_starts_at
      @text_starts_at = tag_ends_at
      @text_length = @tag_name_starts_at - @text_starts_at
      @tag_name_starts_at = tag_name_starts_at
      @tag_name_length = tag_name_length
      @has_self_closing_flag = has_self_closing_flag
      @attributes = attributes
      @duplicate_attributes = duplicate_attributes

      true
    end

    private

    def enqueue_anonymous_update(update)
      @lexical_updates[@next_lexical_key] = update
      @next_lexical_key += 1
    end

    def escape_attribute_value(value)
      value.to_s.b.gsub(/[<>&"']/n) { |char| ATTRIBUTE_ESCAPES[char] }
    end

    # WordPress rejects more characters than HTML5 strictly forbids, to keep risky names
    # from travelling deeper into the stack.
    # Legacy: class-wp-html-tag-processor.php:4595.
    def valid_attribute_name?(name)
      name_length = name.bytesize
      return false if name_length.zero?
      return false if ByteScan.cspan(name, "\"'>&</ =") != name_length
      return false if ByteScan.cspan(name, CONTROL_CHARACTERS) != name_length
      return false if Utf8.noncharacters?(name)

      true
    end

    def enqueue_class_update(class_name, action)
      return false if @parser_state != STATE_MATCHED_TAG || @is_closing_tag

      class_name = class_name.b

      if @compat_mode != QUIRKS_MODE
        @classname_updates[class_name] = action
        return true
      end

      # In quirks mode class names match ASCII-case-insensitively, so an existing entry
      # in a different casing has to be updated in place rather than added alongside.
      existing = @classname_updates.keys.find do |updated_name|
        updated_name.bytesize == class_name.bytesize && updated_name.downcase == class_name.downcase
      end

      @classname_updates[existing || class_name] = action
      true
    end

    # Legacy: class-wp-html-tag-processor.php:1414 / :1434.
    def skip_rawtext(tag_name)
      # RAWTEXT and RCDATA differ only in whether character references are decoded, and
      # the inner markup is not exposed, so one implementation serves both.
      skip_rcdata(tag_name)
    end

    def skip_rcdata(tag_name) # rubocop:disable Metrics/AbcSize
      html = @html
      doc_length = html.bytesize
      tag_name = tag_name.b
      tag_length = tag_name.bytesize

      at = @bytes_already_parsed

      while !at.nil? && at < doc_length
        at = html.index("</", at)
        @tag_name_starts_at = at

        return false if at.nil? || (at + 2 + tag_length) >= doc_length

        at += 2

        mismatch_at = nil
        tag_length.times do |i|
          tag_char = tag_name.getbyte(i)
          html_char = html.getbyte(at + i)
          upper = html_char.between?(0x61, 0x7A) ? html_char - 32 : html_char
          if html_char != tag_char && upper != tag_char
            mismatch_at = i
            break
          end
        end

        if mismatch_at
          at += mismatch_at
          next
        end

        at += tag_length
        @bytes_already_parsed = at

        return false if at >= doc_length

        char = html.byteslice(at, 1)
        next unless [" ", "\t", "\f", "\r", "\n", "/", ">"].include?(char)

        nil while parse_next_attribute

        at = @bytes_already_parsed
        return false if at >= doc_length

        if html.byteslice(at, 1) == ">"
          @bytes_already_parsed = at + 1
          return true
        end

        return false if at + 1 >= doc_length

        if html.byteslice(at, 1) == "/" && html.byteslice(at + 1, 1) == ">"
          @bytes_already_parsed = at + 2
          return true
        end
      end

      false
    end

    # Legacy: class-wp-html-tag-processor.php:1523.
    def skip_script_data # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
      state = "unescaped"
      html = @html
      doc_length = html.bytesize
      at = @bytes_already_parsed
      closer_potentially_starts_at = nil

      while at < doc_length
        at += ByteScan.cspan(html, "-<", at)

        # Terminating a complete script element requires at least eight more bytes,
        # so a shorter remainder can only mean the document was truncated.
        return false if at + 8 >= doc_length

        if html.getbyte(at) == 0x2D && html.getbyte(at + 1) == 0x2D && html.getbyte(at + 2) == 0x3E
          at += 3
          state = "unescaped"
          next
        end

        byte = html.getbyte(at)
        at += 1
        next unless byte == 0x3C # `<`

        if state == "unescaped" && html.getbyte(at) == 0x21 &&
           html.getbyte(at + 1) == 0x2D && html.getbyte(at + 2) == 0x2D
          at += 3
          at += ByteScan.span(html, "-", at)
          if at < doc_length && html.getbyte(at) == 0x3E
            at += 1
            next
          end
          state = "escaped"
          next
        end

        if html.getbyte(at) == 0x2F # `/`
          closer_potentially_starts_at = at - 1
          is_closing = true
          at += 1
        else
          is_closing = false
        end

        next unless html.byteslice(at, 6)&.downcase == "script"

        at += 6
        char = html.byteslice(at, 1)
        next unless [">", " ", "\n", "/", "\t", "\f", "\r"].include?(char)

        if state == "escaped" && !is_closing
          state = "double-escaped"
          next
        end

        if state == "double-escaped" && is_closing
          state = "escaped"
          next
        end

        if is_closing
          @bytes_already_parsed = closer_potentially_starts_at
          @tag_name_starts_at = closer_potentially_starts_at
          return false if @bytes_already_parsed >= doc_length

          nil while parse_next_attribute

          return false if @bytes_already_parsed >= doc_length

          if html.byteslice(@bytes_already_parsed, 1) == ">"
            @bytes_already_parsed += 1
            return true
          end
        end

        at += 1
      end

      false
    end

    # Legacy: class-wp-html-tag-processor.php:1734.
    def parse_next_tag # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      after_tag

      html = @html
      doc_length = html.bytesize
      was_at = @bytes_already_parsed
      at = was_at

      while at < doc_length
        at = html.index("<", at)
        break if at.nil?

        if at > was_at
          # A `<` that cannot start a token is plaintext — `<3` is a heart, not a tag.
          if ByteScan.span(html, TAG_OPEN_FOLLOWERS, at + 1, 1) != 1
            at += 1
            next
          end

          @parser_state = STATE_TEXT_NODE
          @token_starts_at = was_at
          @token_length = at - was_at
          @text_starts_at = was_at
          @text_length = @token_length
          @bytes_already_parsed = at
          return true
        end

        @token_starts_at = at

        if at + 1 < doc_length && html.byteslice(at + 1, 1) == "/"
          @is_closing_tag = true
          at += 1
        else
          @is_closing_tag = false
        end

        tag_name_prefix_length = ByteScan.span(html, ASCII_ALPHA, at + 1)
        if tag_name_prefix_length.positive?
          at += 1
          @parser_state = STATE_MATCHED_TAG
          @tag_name_starts_at = at
          @tag_name_length = tag_name_prefix_length +
                             ByteScan.cspan(html, " \t\f\r\n/>", at + tag_name_prefix_length)
          @bytes_already_parsed = at + @tag_name_length
          return true
        end

        if at + 1 >= doc_length
          @parser_state = STATE_INCOMPLETE_INPUT
          return false
        end

        if !@is_closing_tag && html.byteslice(at + 1, 1) == "!"
          result = parse_markup_declaration(html, at, doc_length)
          return result unless result.nil?

          next
        end

        # `</>` is a missing end tag name, which is ignored; `<>` is plaintext.
        if html.byteslice(at + 1, 1) == ">"
          unless @is_closing_tag
            at += 1
            next
          end

          @parser_state = STATE_PRESUMPTUOUS_TAG
          @token_length = at + 2 - @token_starts_at
          @bytes_already_parsed = at + 2
          return true
        end

        if !@is_closing_tag && html.byteslice(at + 1, 1) == "?"
          return parse_processing_instruction(html, at, doc_length)
        end

        # A non-alpha first character in a tag closer produces a "funky comment".
        if @is_closing_tag
          if at + 3 > doc_length
            @parser_state = STATE_INCOMPLETE_INPUT
            return false
          end

          closer_at = html.index(">", at + 2)
          if closer_at.nil?
            @parser_state = STATE_INCOMPLETE_INPUT
            return false
          end

          @parser_state = STATE_FUNKY_COMMENT
          @token_length = closer_at + 1 - @token_starts_at
          @text_starts_at = @token_starts_at + 2
          @text_length = closer_at - @text_starts_at
          @bytes_already_parsed = closer_at + 1
          return true
        end

        at += 1
      end

      # Not an incomplete parse: nothing can remain but a text node.
      @parser_state = STATE_TEXT_NODE
      @token_starts_at = was_at
      @token_length = doc_length - was_at
      @text_starts_at = was_at
      @text_length = @token_length
      @bytes_already_parsed = doc_length
      true
    end

    # `<!…` — comment, DOCTYPE, CDATA section, or bogus comment.
    # Returns true/false when the token was decided, or nil to keep scanning.
    def parse_markup_declaration(html, at, doc_length) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      if html.byteslice(at + 2, 2) == "--"
        closer_at = at + 4
        if doc_length <= closer_at
          @parser_state = STATE_INCOMPLETE_INPUT
          return false
        end

        # Abruptly-closed empty comments are a run of dashes followed by `>`.
        span_of_dashes = ByteScan.span(html, "-", closer_at)
        if doc_length <= span_of_dashes + closer_at
          @parser_state = STATE_INCOMPLETE_INPUT
          return false
        end

        if html.byteslice(closer_at + span_of_dashes, 1) == ">"
          @parser_state = STATE_COMMENT
          @comment_type = COMMENT_AS_ABRUPTLY_CLOSED_COMMENT
          @token_length = closer_at + span_of_dashes + 1 - @token_starts_at

          if span_of_dashes >= 2
            @comment_type = COMMENT_AS_HTML_COMMENT
            @text_starts_at = @token_starts_at + 4
            @text_length = span_of_dashes - 2
          end

          @bytes_already_parsed = closer_at + span_of_dashes + 1
          return true
        end

        # Comments close on `-->` or on the invalid `--!>`; first occurrence wins.
        closer_at -= 1
        loop do
          closer_at += 1
          break unless closer_at < doc_length

          closer_at = html.index("--", closer_at)
          if closer_at.nil?
            @parser_state = STATE_INCOMPLETE_INPUT
            return false
          end

          if closer_at + 2 < doc_length && html.byteslice(closer_at + 2, 1) == ">"
            @parser_state = STATE_COMMENT
            @comment_type = COMMENT_AS_HTML_COMMENT
            @token_length = closer_at + 3 - @token_starts_at
            @text_starts_at = @token_starts_at + 4
            @text_length = closer_at - @text_starts_at
            @bytes_already_parsed = closer_at + 3
            return true
          end

          next unless closer_at + 3 < doc_length &&
                      html.byteslice(closer_at + 2, 1) == "!" &&
                      html.byteslice(closer_at + 3, 1) == ">"

          @parser_state = STATE_COMMENT
          @comment_type = COMMENT_AS_HTML_COMMENT
          @token_length = closer_at + 4 - @token_starts_at
          @text_starts_at = @token_starts_at + 4
          @text_length = closer_at - @text_starts_at
          @bytes_already_parsed = closer_at + 4
          return true
        end
      end

      if doc_length > at + 8 && html.byteslice(at + 2, 7).downcase == "doctype"
        closer_at = html.index(">", at + 9)
        if closer_at.nil?
          @parser_state = STATE_INCOMPLETE_INPUT
          return false
        end

        @parser_state = STATE_DOCTYPE
        @token_length = closer_at + 1 - @token_starts_at
        @text_starts_at = @token_starts_at + 9
        @text_length = closer_at - @text_starts_at
        @bytes_already_parsed = closer_at + 1
        return true
      end

      if @parsing_namespace != "html" && html.bytesize > at + 8 &&
         html.byteslice(at + 2, 7) == "[CDATA["
        closer_at = html.index("]]>", at + 9)
        if closer_at.nil?
          @parser_state = STATE_INCOMPLETE_INPUT
          return false
        end

        @parser_state = STATE_CDATA_NODE
        @text_starts_at = at + 9
        @text_length = closer_at - @text_starts_at
        @token_length = closer_at + 3 - @token_starts_at
        @bytes_already_parsed = closer_at + 3
        return true
      end

      # Anything else is an incorrectly-opened comment: a bogus comment to the next `>`.
      closer_at = html.index(">", at + 1)
      if closer_at.nil?
        @parser_state = STATE_INCOMPLETE_INPUT
        return false
      end

      @parser_state = STATE_COMMENT
      @comment_type = COMMENT_AS_INVALID_HTML
      @token_length = closer_at + 1 - @token_starts_at
      @text_starts_at = @token_starts_at + 2
      @text_length = closer_at - @text_starts_at
      @bytes_already_parsed = closer_at + 1

      # Identify nodes that would be CDATA if HTML had CDATA sections.
      if @token_length >= 10 &&
         html.byteslice(@token_starts_at + 2, 7) == "[CDATA[" &&
         html.byteslice(closer_at - 1, 1) == "]" &&
         html.byteslice(closer_at - 2, 1) == "]"
        @parser_state = STATE_COMMENT
        @comment_type = COMMENT_AS_CDATA_LOOKALIKE
        @text_starts_at += 7
        @text_length -= 9
      end

      true
    end

    # `<?…` — a processing instruction, or a bogus comment when the target is invalid.
    # Legacy: class-wp-html-tag-processor.php:2040.
    def parse_processing_instruction(html, at, doc_length) # rubocop:disable Metrics/AbcSize
      closer_at = html.index(">", at + 2)
      if closer_at.nil?
        @parser_state = STATE_INCOMPLETE_INPUT
        return false
      end

      target_at = at + 2
      target_length = 0
      first_char = html.byteslice(target_at, 1)
      if first_char && (first_char.match?(/[a-zA-Z_]/n))
        target_length = 1 + ByteScan.span(html, PI_TARGET_TAIL, target_at + 1)
      end

      terminator = html.byteslice(target_at + target_length, 1)
      is_valid_pi = target_length != 0 &&
                    !terminator.nil? &&
                    " \t\f\r\n?>".include?(terminator) &&
                    !(target_length == 3 && html.byteslice(target_at, 3).downcase == "xml") &&
                    !(target_length == 14 && html.byteslice(target_at, 14).downcase == "xml-stylesheet")

      if is_valid_pi
        data_at = target_at + target_length
        data_at += ByteScan.span(html, WHITESPACE, data_at)

        data_length = closer_at - data_at
        data_length -= 1 if data_length.positive? && html.byteslice(closer_at - 1, 1) == "?"

        @parser_state = STATE_PROCESSING_INSTRUCTION
        @tag_name_starts_at = target_at
        @tag_name_length = target_length
        @token_length = closer_at + 1 - @token_starts_at
        @text_starts_at = data_at
        @text_length = data_length
        @bytes_already_parsed = closer_at + 1
        return true
      end

      @parser_state = STATE_COMMENT
      @comment_type = COMMENT_AS_INVALID_HTML
      @token_length = closer_at + 1 - @token_starts_at
      @text_starts_at = @token_starts_at + 2
      @text_length = closer_at - @text_starts_at
      @bytes_already_parsed = closer_at + 1

      # Recognise XML-like processing instructions, which HTML turns into bogus comments.
      if @token_length >= 5 && html.byteslice(closer_at - 1, 1) == "?"
        comment_text = html.byteslice(@token_starts_at + 2, @token_length - 4)
        pi_target_length = ByteScan.span(comment_text, "#{ASCII_ALPHA}:_")

        if pi_target_length.positive?
          pi_target_length += ByteScan.span(comment_text, "#{ASCII_ALPHA}0123456789:_-.",
                                            pi_target_length)

          @comment_type = COMMENT_AS_PI_NODE_LOOKALIKE
          @tag_name_starts_at = @token_starts_at + 2
          @tag_name_length = pi_target_length
          @text_starts_at += pi_target_length
          @text_length -= pi_target_length + 1
        end
      end

      true
    end

    # Legacy: class-wp-html-tag-processor.php:2213.
    def parse_next_attribute # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      doc_length = @html.bytesize

      skipped_length = ByteScan.span(@html, " \t\f\r\n/", @bytes_already_parsed)
      @bytes_already_parsed += skipped_length
      if @bytes_already_parsed >= doc_length
        @parser_state = STATE_INCOMPLETE_INPUT
        return false
      end

      if @html.byteslice(@bytes_already_parsed, 1) == ">"
        if skipped_length.positive? && @html.byteslice(@bytes_already_parsed - 1, 1) == "/"
          @has_self_closing_flag = true
        end
        return false
      end

      # An equals sign is part of the attribute name if it is the first byte seen.
      name_length = if @html.byteslice(@bytes_already_parsed, 1) == "="
                      1 + ByteScan.cspan(@html, "=/> \t\f\r\n", @bytes_already_parsed + 1)
                    else
                      ByteScan.cspan(@html, "=/> \t\f\r\n", @bytes_already_parsed)
                    end

      return false if name_length.zero? || @bytes_already_parsed + name_length >= doc_length

      attribute_start = @bytes_already_parsed
      attribute_name = @html.byteslice(attribute_start, name_length)
      @bytes_already_parsed += name_length
      if @bytes_already_parsed >= doc_length
        @parser_state = STATE_INCOMPLETE_INPUT
        return false
      end

      skip_whitespace
      if @bytes_already_parsed >= doc_length
        @parser_state = STATE_INCOMPLETE_INPUT
        return false
      end

      has_value = @html.byteslice(@bytes_already_parsed, 1) == "="
      if has_value
        @bytes_already_parsed += 1
        skip_whitespace
        if @bytes_already_parsed >= doc_length
          @parser_state = STATE_INCOMPLETE_INPUT
          return false
        end

        quote = @html.byteslice(@bytes_already_parsed, 1)
        if quote == "'" || quote == '"'
          value_start = @bytes_already_parsed + 1
          end_quote_at = @html.index(quote, value_start) || doc_length
          value_length = end_quote_at - value_start
          attribute_end = end_quote_at + 1
          @bytes_already_parsed = attribute_end
        else
          value_start = @bytes_already_parsed
          value_length = ByteScan.cspan(@html, "> \t\f\r\n", value_start)
          attribute_end = value_start + value_length
          @bytes_already_parsed = attribute_end
        end
      else
        value_start = @bytes_already_parsed
        value_length = 0
        attribute_end = attribute_start + name_length
      end

      if attribute_end >= doc_length
        @parser_state = STATE_INCOMPLETE_INPUT
        return false
      end

      return true if @is_closing_tag

      # The tokenizer replaces NULL bytes in attribute names with U+FFFD, and duplicate
      # names differing only in case are the same attribute.
      comparable_name = attribute_name.gsub("\x00", Decoder::REPLACEMENT_CHARACTER).downcase

      unless @attributes.key?(comparable_name)
        @attributes[comparable_name] = AttributeToken.new(
          attribute_name, value_start, value_length, attribute_start,
          attribute_end - attribute_start, !has_value
        )
        return true
      end

      # Track duplicates so that removing the attribute removes all of them together.
      duplicate_span = Span.new(attribute_start, attribute_end - attribute_start)
      @duplicate_attributes ||= {}
      (@duplicate_attributes[comparable_name] ||= []) << duplicate_span

      true
    end

    # Legacy: class-wp-html-tag-processor.php:2375.
    def skip_whitespace
      @bytes_already_parsed += ByteScan.span(@html, WHITESPACE, @bytes_already_parsed)
    end

    # Legacy: class-wp-html-tag-processor.php:2385.
    def after_tag
      class_name_updates_to_attributes_updates

      get_updated_html if @lexical_updates.size > 1000

      @lexical_updates.to_a.each do |name, update|
        # Updates after the cursor must be applied now or they will be missed.
        if update.start >= @bytes_already_parsed
          get_updated_html
          break
        end

        next if name.is_a?(Integer)

        @lexical_updates.delete(name)
        enqueue_anonymous_update(update)
      end

      @token_starts_at = nil
      @token_length = nil
      @has_self_closing_flag = false
      @tag_name_starts_at = nil
      @tag_name_length = nil
      @text_starts_at = 0
      @text_length = 0
      @is_closing_tag = nil
      @attributes = {}
      @comment_type = nil
      @text_node_classification = TEXT_IS_GENERIC
      @duplicate_attributes = nil
    end

    # Folds queued `add_class`/`remove_class` calls into one `class` attribute update.
    # Legacy: class-wp-html-tag-processor.php:2449.
    def class_name_updates_to_attributes_updates # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      return if @classname_updates.empty?

      existing_class = get_enqueued_attribute_value("class")
      existing_class = "".b if existing_class == :none || existing_class == true

      if existing_class == false && @attributes.key?("class")
        existing_class = get_decoded_attribute_value(@attributes["class"])
      end

      existing_class = "".b if existing_class == false

      class_value = +"".b
      at = 0
      modified = false
      seen = []
      to_remove = []
      is_quirks = @compat_mode == QUIRKS_MODE

      @classname_updates.each do |updated_name, action|
        next unless action == REMOVE_CLASS

        to_remove << (is_quirks ? updated_name.downcase : updated_name)
      end

      existing_class_length = existing_class.bytesize
      while at < existing_class_length
        ws_at = at
        ws_length = ByteScan.span(existing_class, WHITESPACE, ws_at)
        at += ws_length

        name_length = ByteScan.cspan(existing_class, WHITESPACE, at)
        break if name_length.zero?

        name = existing_class.byteslice(at, name_length)
        comparable_class_name = is_quirks ? name.downcase : name
        at += name_length

        if to_remove.include?(comparable_class_name)
          modified = true
          next
        end

        next if seen.include?(comparable_class_name)

        seen << comparable_class_name

        # Preserving the existing inter-class whitespace keeps the diff small.
        class_value << existing_class.byteslice(ws_at, ws_length) unless class_value.empty?
        class_value << name
      end

      @classname_updates.each do |name, operation|
        comparable_name = is_quirks ? name.downcase : name
        next unless operation == ADD_CLASS && !seen.include?(comparable_name)

        modified = true
        class_value << " " unless class_value.empty?
        class_value << name
      end

      @classname_updates = {}
      return unless modified

      if class_value.bytesize.positive?
        set_attribute("class", class_value)
      else
        remove_attribute("class")
      end
    end

    # Applies every queued splice in ascending order, shifting the cursor and bookmarks.
    # Legacy: class-wp-html-tag-processor.php:2607.
    def apply_attributes_updates(shift_this_point) # rubocop:disable Metrics/AbcSize
      return 0 if @lexical_updates.empty?

      accumulated_shift_for_given_point = 0

      # Splices must be made in lexical order or they mangle each other.
      updates = @lexical_updates.values.sort do |a, b|
        by_start = a.start - b.start
        if by_start != 0
          by_start
        else
          by_text = a.text <=> b.text
          by_text != 0 ? by_text : a.length - b.length
        end
      end

      bytes_already_copied = 0
      output_buffer = +"".b
      updates.each do |diff|
        shift = diff.text.bytesize - diff.length

        @bytes_already_parsed += shift if diff.start < @bytes_already_parsed
        accumulated_shift_for_given_point += shift if diff.start < shift_this_point

        output_buffer << @html.byteslice(bytes_already_copied, diff.start - bytes_already_copied)
        output_buffer << diff.text
        bytes_already_copied = diff.start + diff.length
      end

      @html = output_buffer + @html.byteslice(bytes_already_copied,
                                              @html.bytesize - bytes_already_copied)

      # Shift bookmarks so they keep pointing at the same token, and drop any bookmark
      # whose whole span was overwritten rather than let it point at the wrong bytes.
      @bookmarks.to_a.each do |bookmark_name, bookmark|
        bookmark_end = bookmark.start + bookmark.length
        head_delta = 0
        tail_delta = 0
        released = false

        updates.each do |diff|
          diff_end = diff.start + diff.length

          break if bookmark.start < diff.start && bookmark_end < diff.start

          if bookmark.start >= diff.start && bookmark_end < diff_end
            release_bookmark(bookmark_name)
            released = true
            break
          end

          delta = diff.text.bytesize - diff.length
          head_delta += delta if bookmark.start >= diff.start
          tail_delta += delta if bookmark_end >= diff_end
        end

        next if released

        bookmark.start += head_delta
        bookmark.length += tail_delta - head_delta
      end

      @lexical_updates = {}

      accumulated_shift_for_given_point
    end

    # Returns the enqueued value for an attribute:
    #   * `false` when nothing is enqueued (distinct from "removed"),
    #   * `:none` when the attribute is enqueued for removal,
    #   * `true` for an enqueued boolean attribute,
    #   * otherwise the decoded String value.
    # Legacy: class-wp-html-tag-processor.php:2799.
    def get_enqueued_attribute_value(comparable_name)
      return false unless @parser_state == STATE_MATCHED_TAG

      update = @lexical_updates[comparable_name]
      return false if update.nil?

      enqueued_text = update.text

      # Removed attributes erase the entire span.
      return :none if enqueued_text.empty?

      # A boolean attribute update is just the name, with no `=`.
      equals_at = enqueued_text.index("=")
      return true if equals_at.nil?

      enqueued_value = enqueued_text.byteslice(equals_at + 2,
                                               enqueued_text.bytesize - equals_at - 3)
      utf8(Decoder.decode("attribute", enqueued_value))
    end

    # Legacy: class-wp-html-tag-processor.php:2936.
    def get_decoded_attribute_value(attribute)
      raw_value = @html.byteslice(attribute.value_starts_at, attribute.value_length)
      raw_value = raw_value.gsub("\r\n", "\n").gsub("\r", "\n")
      raw_value = raw_value.gsub("\x00", Decoder::REPLACEMENT_CHARACTER)
      Decoder.decode("attribute", raw_value)
    end

    # Legacy: class-wp-html-tag-processor.php:4979.
    def parse_query(query)
      return if !query.nil? && query == @last_query

      @last_query = query
      @sought_tag_name = nil
      @sought_class_name = nil
      @sought_match_offset = 1
      @stop_on_tag_closers = false

      if query.is_a?(String)
        @sought_tag_name = query
        return
      end

      return if query.nil?
      return unless query.is_a?(Hash)

      @sought_tag_name = query[:tag_name] if query[:tag_name].is_a?(String)
      @sought_class_name = query[:class_name] if query[:class_name].is_a?(String)
      if query[:match_offset].is_a?(Integer) && query[:match_offset].positive?
        @sought_match_offset = query[:match_offset]
      end
      @stop_on_tag_closers = query[:tag_closers] == "visit" if query.key?(:tag_closers)
    end

    # Legacy: class-wp-html-tag-processor.php:5037.
    def matches?
      return false if @is_closing_tag && !@stop_on_tag_closers

      if @sought_tag_name
        tag_name = get_tag
        return false if @sought_tag_name.bytesize != tag_name.bytesize
        return false unless tag_name.b.downcase == @sought_tag_name.b.downcase
      end

      return false if !@sought_class_name.nil? && !has_class?(@sought_class_name)

      true
    end
  end
end
