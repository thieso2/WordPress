# frozen_string_literal: true

module Markup
  # An HTML5 tree-construction parser built on top of the byte-level Tag Processor.
  #
  # BR-MIGRATE-223 — this class implements the HTML5 tree construction algorithm,
  # including the stack of open elements and the list of active formatting elements,
  # without ever building a tree. Every element the algorithm opens or closes is reported
  # as a token, in document order, so callers see the same structure a DOM would give them
  # while the document stays a string of bytes (BR-MIGRATE-220).
  #
  # BR-MIGRATE-224 — fragment parsing needs a context element; `create_fragment` defaults
  # to `<body>`, which is the only context the legacy accepts through that entry point.
  #
  # BR-MIGRATE-225 — where the algorithm is not implemented, this class raises
  # Markup::UnsupportedException instead of producing an incorrect result.
  #
  # BR-MIGRATE-226 — `get_breadcrumbs` and `matches_breadcrumbs` answer ancestor questions
  # directly from the stack of open elements, with no DOM and no XPath.
  #
  # Legacy: wp-includes/html-api/class-wp-html-processor.php.
  class Processor < TagProcessor # rubocop:disable Metrics/ClassLength
    # Legacy: class-wp-html-processor.php:159.
    MAX_BOOKMARKS = 10_000

    PROCESS_NEXT_NODE = "process-next-node"
    REPROCESS_CURRENT_NODE = "reprocess-current-node"
    PROCESS_CURRENT_NODE = "process-current-node"

    ERROR_UNSUPPORTED = "unsupported"
    ERROR_EXCEEDED_MAX_BOOKMARKS = "exceeded-max-bookmarks"

    CONSTRUCTOR_UNLOCK_CODE =
      "Use WP_HTML_Processor::create_fragment() instead of calling the class constructor directly."

    # Raised internally when no bookmark can be allocated; callers see `false` plus
    # `get_last_error`. Legacy: class-wp-html-processor.php:5123 (`throw new Exception`).
    class BookmarkAllocationError < StandardError; end

    # Elements whose contents need a special tokenizer state and therefore cannot serve as
    # a fragment context. Legacy: class-wp-html-processor.php:516.
    UNSUPPORTED_CONTEXT_ELEMENTS = %w[
      IFRAME NOEMBED NOFRAMES SCRIPT STYLE TEXTAREA TITLE XMP PLAINTEXT
    ].freeze

    # Legacy: class-wp-html-processor.php:1005.
    ATOMIC_HTML_ELEMENTS = %w[IFRAME NOEMBED NOFRAMES SCRIPT STYLE TEXTAREA TITLE XMP].freeze

    # Legacy: class-wp-html-processor.php:5803.
    ELEMENTS_WITH_IMPLIED_END_TAGS = %w[DD DT LI OPTGROUP OPTION P RB RP RT RTC].freeze
    ELEMENTS_WITH_IMPLIED_END_TAGS_THOROUGHLY = %w[
      CAPTION COLGROUP DD DT LI OPTGROUP OPTION P RB RP RT RTC TBODY TD TFOOT TH THEAD TR
    ].freeze

    # Legacy: class-wp-html-processor.php:6408.
    SPECIAL_ELEMENTS = %w[
      ADDRESS APPLET AREA ARTICLE ASIDE BASE BASEFONT BGSOUND BLOCKQUOTE BODY BR BUTTON
      CAPTION CENTER COL COLGROUP DD DETAILS DIR DIV DL DT EMBED FIELDSET FIGCAPTION FIGURE
      FOOTER FORM FRAME FRAMESET H1 H2 H3 H4 H5 H6 HEAD HEADER HGROUP HR HTML IFRAME IMG
      INPUT KEYGEN LI LINK LISTING MAIN MARQUEE MENU META NAV NOEMBED NOFRAMES NOSCRIPT
      OBJECT OL P PARAM PLAINTEXT PRE SCRIPT SEARCH SECTION SELECT SOURCE STYLE SUMMARY
      TABLE TBODY TD TEMPLATE TEXTAREA TFOOT TH THEAD TITLE TR TRACK UL WBR XMP
    ].freeze
    SPECIAL_FOREIGN_ELEMENTS = [
      "math MI", "math MO", "math MN", "math MS", "math MTEXT", "math ANNOTATION-XML",
      "svg DESC", "svg FOREIGNOBJECT", "svg TITLE"
    ].freeze

    # Legacy: class-wp-html-processor.php:6529.
    VOID_ELEMENTS = %w[
      AREA BASE BASEFONT BGSOUND BR COL EMBED FRAME HR IMG INPUT KEYGEN LINK META PARAM
      SOURCE TRACK WBR
    ].freeze

    HEADINGS = %w[H1 H2 H3 H4 H5 H6].freeze

    attr_reader :state, :context_node

    # Creates a fragment parser for HTML found inside a context element.
    #
    # BR-MIGRATE-224 — a fragment cannot be parsed without knowing where it will live:
    # `<td>x</td>` parsed in BODY context loses its cell entirely, while the same bytes in
    # TABLE context produce TBODY > TR > TD. The context defaults to `<body>` and, exactly
    # as in the legacy, that is the only value this entry point accepts; anything else
    # returns nil rather than guessing. The context is established by running a full
    # parser over `<!DOCTYPE html><body>` and creating the fragment at the node it lands
    # on, which is what puts HTML and BODY into the breadcrumbs from the first token.
    #
    # Legacy: class-wp-html-processor.php:300.
    def self.create_fragment(html, context = "<body>", encoding = "UTF-8")
      return nil if context != "<body>" || encoding != "UTF-8"
      return nil unless html.is_a?(String)

      context_processor = create_full_parser("<!DOCTYPE html>#{context}", encoding)
      return nil if context_processor.nil?

      while context_processor.next_tag
        context_processor.set_bookmark("final_node") unless context_processor.send(:virtual?)
      end

      unless context_processor.has_bookmark?("final_node") && context_processor.seek("final_node")
        return nil
      end

      context_processor.send(:create_fragment_at_current_node, html)
    end

    # Creates a parser for a whole document.
    #
    # Legacy: class-wp-html-processor.php:354.
    def self.create_full_parser(html, known_definite_encoding = "UTF-8")
      return nil if known_definite_encoding != "UTF-8"
      return nil unless html.is_a?(String)

      processor = new(html, CONSTRUCTOR_UNLOCK_CODE)
      processor.state.encoding = known_definite_encoding
      processor.state.encoding_confidence = "certain"
      processor
    end

    # Legacy: class-wp-html-processor.php:388.
    def initialize(html, _use_the_static_create_methods_instead = nil)
      super(html)

      @state = ProcessorState.new
      @last_error = nil
      @unsupported_exception = nil
      @element_queue = []
      @current_element = nil
      @breadcrumbs = []
      @context_node = nil
      @bookmark_counter = 0

      @state.stack_of_open_elements.set_push_handler(method(:on_element_pushed))
      @state.stack_of_open_elements.set_pop_handler(method(:on_element_popped))
    end

    # Legacy: class-wp-html-processor.php:647.
    def get_last_error
      @last_error
    end

    # Context for why the parser aborted on unsupported HTML, if it did.
    #
    # BR-MIGRATE-225. Legacy: class-wp-html-processor.php:662.
    def get_unsupported_exception
      @unsupported_exception
    end

    # Advances to the next tag matching `query`.
    #
    # `query` may be nil, a tag-name String, or a Hash accepting `tag_name`,
    # `tag_closers`, `match_offset`, `class_name` and `breadcrumbs`.
    #
    # BR-MIGRATE-226 (the `breadcrumbs` form). Legacy: class-wp-html-processor.php:690.
    def next_tag(query = nil) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      query = { breadcrumbs: [query] } if query.is_a?(String)
      return false if !query.nil? && !query.is_a?(Hash)

      visit_closers = query.is_a?(Hash) && query[:tag_closers] == "visit"

      if query.nil?
        while next_token
          next if get_token_type != "#tag"
          return true if !tag_closer? || visit_closers
        end
        return false
      end

      tag_name = query[:tag_name]&.upcase
      needs_class = query[:class_name].is_a?(String) ? query[:class_name] : nil

      unless query.key?(:breadcrumbs) && query[:breadcrumbs].is_a?(Array)
        while next_token
          next if get_token_type != "#tag"
          next if tag_name && tag_name != get_token_name
          next if needs_class && !has_class?(needs_class)
          return true if !tag_closer? || visit_closers
        end
        return false
      end

      breadcrumbs = query[:breadcrumbs]
      match_offset = query[:match_offset] ? query[:match_offset].to_i : 1

      while match_offset.positive? && next_token
        next if get_token_type != "#tag" || tag_closer?
        next if needs_class && !has_class?(needs_class)

        if matches_breadcrumbs(breadcrumbs)
          match_offset -= 1
          return true if match_offset.zero?
        end
      end

      false
    end

    # Legacy: class-wp-html-processor.php:782.
    def next_token
      next_visitable_token
    end

    # Legacy: class-wp-html-processor.php:884.
    def tag_closer?
      if virtual?
        @current_element.operation == StackEvent::POP && get_token_type == "#tag"
      else
        base_class_tag_closer?
      end
    end

    # Whether the currently-matched tag sits at the given ancestor path.
    #
    # BR-MIGRATE-226 — ancestor querying with no DOM and no XPath. The path is matched
    # from the matched element upward, one crumb per ancestor; `*` matches exactly one
    # element. There is deliberately no `**` (match-any-number) syntax: it would require
    # backtracking, and the whole point of this API is that a query costs no more than the
    # depth of the current element.
    #
    # Legacy: class-wp-html-processor.php:931.
    def matches_breadcrumbs(breadcrumbs)
      # Everything matches when there are zero constraints.
      return true if breadcrumbs.empty?

      crumb = breadcrumbs.last
      return false if crumb != "*" && get_tag != crumb.upcase

      # Walk the breadcrumb list from its end backwards alongside the open elements.
      crumb_index = breadcrumbs.length - 1
      (@breadcrumbs.length - 1).downto(0) do |i|
        node = @breadcrumbs[i]
        crumb = breadcrumbs[crumb_index].upcase

        return false if crumb != "*" && node != crumb

        crumb_index -= 1
        return true if crumb_index.negative?
      end

      false
    end

    # Whether the matched node will be followed by a closing token.
    #
    # Legacy: class-wp-html-processor.php:978.
    def expects_closer(node = nil)
      token_name = node ? node.node_name : get_token_name
      return nil if token_name.nil?

      token_namespace = node ? node.namespace : get_namespace
      token_has_self_closing = node ? node.has_self_closing_flag : has_self_closing_flag?

      !(
        # Comments, text nodes, and other atomic tokens.
        token_name.start_with?("#") ||
        # Doctype declarations.
        token_name == "html" ||
        # Void elements.
        (token_namespace == "html" && self.class.void?(token_name)) ||
        # Special atomic elements.
        (token_namespace == "html" && ATOMIC_HTML_ELEMENTS.include?(token_name)) ||
        # Self-closing elements in foreign content.
        (token_namespace != "html" && token_has_self_closing)
      )
    end

    # The ancestor path of the currently-matched node, outermost first.
    #
    # BR-MIGRATE-226 — this is maintained incrementally as stack events are visited, so
    # asking for it is free; it is not recomputed by walking a tree.
    #
    # Legacy: class-wp-html-processor.php:1202.
    def get_breadcrumbs
      # PHP arrays are values: `return $this->breadcrumbs;` hands the caller an
      # independent copy. Ruby Arrays are references, and `@breadcrumbs` is mutated in
      # place on every stack event, so the reference has to be copied to preserve the
      # legacy's caller-visible semantics.
      @breadcrumbs.dup
    end

    # Legacy: class-wp-html-processor.php:1231.
    def get_current_depth
      @breadcrumbs.length
    end

    # Legacy: class-wp-html-processor.php:5138.
    def get_namespace
      return super if @current_element.nil?

      @current_element.token.namespace
    end

    # Legacy: class-wp-html-processor.php:5167.
    def get_tag
      return nil unless @last_error.nil?
      return @current_element.token.node_name if virtual?

      tag_name = super
      tag_name == "IMAGE" && get_namespace == "html" && get_token_type == "#tag" ? "IMG" : tag_name
    end

    # Legacy: class-wp-html-processor.php:5208.
    def has_self_closing_flag?
      virtual? ? false : super
    end

    # Legacy: class-wp-html-processor.php:5232.
    def get_token_name
      virtual? ? @current_element.token.node_name : super
    end

    # Legacy: class-wp-html-processor.php:5263.
    def get_token_type
      return super unless virtual?

      node_name = @current_element.token.node_name
      starting_char = node_name[0]
      return "#tag" if starting_char >= "A" && starting_char <= "Z"
      return "#doctype" if node_name == "html"

      node_name
    end

    # Legacy: class-wp-html-processor.php:5306.
    def get_attribute(name)
      virtual? ? nil : super
    end

    # Legacy: class-wp-html-processor.php:5342.
    def set_attribute(name, value)
      virtual? ? false : super
    end

    # Legacy: class-wp-html-processor.php:5354.
    def remove_attribute(name)
      virtual? ? false : super
    end

    # BR-MIGRATE-222 — unchanged from the Tag Processor except that virtual tokens, which
    # have no text in the document, expose no attributes.
    # Legacy: class-wp-html-processor.php:5384.
    def get_attribute_names_with_prefix(prefix)
      virtual? ? nil : super
    end

    def add_class(class_name)
      virtual? ? false : super
    end

    def remove_class(class_name)
      virtual? ? false : super
    end

    def has_class?(wanted_class)
      virtual? ? nil : super
    end

    def class_list(&block)
      return to_enum(:class_list) unless block
      return if virtual?

      super(&block)
    end

    def get_modifiable_text
      virtual? ? "" : super
    end

    def get_comment_type
      virtual? ? nil : super
    end

    # Bookmarks set by callers are namespaced apart from the ones the parser allocates for
    # its own tokens. BR-MIGRATE-221.
    # Legacy: class-wp-html-processor.php:5749.
    def set_bookmark(bookmark_name)
      return false if virtual?

      base_class_set_bookmark("_#{bookmark_name}")
    end

    # Legacy: class-wp-html-processor.php:5769.
    def has_bookmark?(bookmark_name)
      super("_#{bookmark_name}")
    end

    # Legacy: class-wp-html-processor.php:5512.
    def release_bookmark(bookmark_name)
      super("_#{bookmark_name}")
    end

    # Returns to a bookmarked token, replaying tree construction as needed.
    #
    # BR-MIGRATE-221 / BR-MIGRATE-223 — seeking backwards cannot simply move the cursor,
    # because the stack of open elements and the list of active formatting elements
    # describe the path taken to get here. Going backwards therefore resets both stacks to
    # their initial state (the fragment's context, if there is one) and replays forward.
    #
    # Legacy: class-wp-html-processor.php:5533.
    def seek(bookmark_name) # rubocop:disable Metrics/AbcSize
      get_updated_html

      actual_bookmark_name = "_#{bookmark_name}"
      return false unless @bookmarks.key?(actual_bookmark_name)

      processor_started_at = @state.current_token ? @bookmarks[@state.current_token.bookmark_name].start : 0
      bookmark_starts_at = @bookmarks[actual_bookmark_name].start
      direction = bookmark_starts_at > processor_started_at ? "forward" : "backward"

      rewind_to_start if direction == "backward"

      loop do
        unless virtual?
          return true if @state.current_token &&
                         bookmark_starts_at == @bookmarks[@state.current_token.bookmark_name].start
        end

        break unless next_token
      end

      false
    end

    # Whether the tag name is "special" in the HTML5 sense.
    # Legacy: class-wp-html-processor.php:6408.
    def self.special?(tag_name)
      name = if tag_name.is_a?(String)
               tag_name.upcase
             elsif tag_name.namespace == "html"
               tag_name.node_name.upcase
             else
               "#{tag_name.namespace} #{tag_name.node_name}"
             end

      SPECIAL_ELEMENTS.include?(name) || SPECIAL_FOREIGN_ELEMENTS.include?(name)
    end

    # Legacy: class-wp-html-processor.php:6529.
    def self.void?(tag_name)
      VOID_ELEMENTS.include?(tag_name.upcase)
    end

    protected

    def max_bookmarks
      MAX_BOOKMARKS
    end

    private

    def on_element_pushed(token)
      is_virtual = @state.current_token.nil? || tag_closer?
      same_node = !@state.current_token.nil? && token.node_name == @state.current_token.node_name
      provenance = (!same_node || is_virtual) ? "virtual" : "real"
      @element_queue << StackEvent.new(token, StackEvent::PUSH, provenance)

      change_parsing_namespace(token.integration_node_type ? "html" : token.namespace)
    end

    def on_element_popped(token)
      is_virtual = @state.current_token.nil? || !tag_closer?
      same_node = !@state.current_token.nil? && token.node_name == @state.current_token.node_name
      provenance = (!same_node || is_virtual) ? "virtual" : "real"
      @element_queue << StackEvent.new(token, StackEvent::POP, provenance)

      adjusted_current_node = get_adjusted_current_node

      if adjusted_current_node
        change_parsing_namespace(adjusted_current_node.integration_node_type ? "html" : adjusted_current_node.namespace)
      else
        change_parsing_namespace("html")
      end
    end

    # BR-MIGRATE-224. Legacy: class-wp-html-processor.php:484.
    def create_fragment_at_current_node(html) # rubocop:disable Metrics/AbcSize
      return nil if get_token_type != "#tag" || tag_closer?

      tag_name = @current_element.token.node_name
      namespace = @current_element.token.namespace

      return nil if namespace == "html" && self.class.void?(tag_name)
      # Contexts that require a special tokenizer state are unsupported.
      return nil if namespace == "html" && UNSUPPORTED_CONTEXT_ELEMENTS.include?(tag_name)

      fragment_processor = self.class.new(html, CONSTRUCTOR_UNLOCK_CODE)
      fragment_processor.send(:establish_fragment_context, self, @current_element.token, @compat_mode)
      fragment_processor
    end

    def establish_fragment_context(outer_processor, context_token, compat_mode)
      @compat_mode = compat_mode

      @bookmarks["root-node"] = Span.new(0, 0)
      @state.stack_of_open_elements.push(Token.new("root-node", "HTML", false))

      @bookmarks["context-node"] = Span.new(0, 0)
      @context_node = context_token.dup
      @context_node.bookmark_name = "context-node"
      @state.context_node = @context_node

      @breadcrumbs = ["HTML", @context_node.node_name]

      if @context_node.node_name == "TEMPLATE"
        @state.stack_of_template_insertion_modes << ProcessorState::INSERTION_MODE_IN_TEMPLATE
      end

      reset_insertion_mode_appropriately

      # > Set the parser's form element pointer to the nearest node to the context element
      # > that is a form element […], if any.
      outer_processor.state.stack_of_open_elements.walk_up do |element|
        next unless element.node_name == "FORM" && element.namespace == "html"

        @state.form_element = element.dup
        @state.form_element.bookmark_name = nil
        break
      end

      @state.encoding_confidence = "irrelevant"

      change_parsing_namespace(context_token.integration_node_type ? "html" : context_token.namespace)
    end

    # Stops the parser when it meets markup it cannot process correctly.
    #
    # BR-MIGRATE-225 — the exception carries enough context to reconstruct the failure:
    # which token, at which byte offset, its raw text, and both tree-construction stacks.
    # Legacy: class-wp-html-processor.php:596.
    def bail(message)
      here = @bookmarks[@state.current_token.bookmark_name]
      token = @html.byteslice(here.start, here.length)

      open_elements = @state.stack_of_open_elements.stack.map(&:node_name)
      active_formats = @state.active_formatting_elements.walk_down.map(&:node_name)

      @last_error = ERROR_UNSUPPORTED

      @unsupported_exception = UnsupportedException.new(
        message, @state.current_token.node_name, here.start, utf8(token),
        open_elements, active_formats
      )

      raise @unsupported_exception
    end

    # Legacy: class-wp-html-processor.php:899.
    def virtual?
      !@current_element.nil? && @current_element.provenance == "virtual"
    end

    # Legacy: class-wp-html-processor.php:804.
    def next_visitable_token # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      loop do
        @current_element = nil

        return false unless @last_error.nil?

        if @element_queue.empty?
          next if step

          return false unless @last_error.nil?
        end

        @current_element = @element_queue.shift
        if @current_element.nil?
          # No tokens left, so close all remaining open elements.
          nil while @state.stack_of_open_elements.pop

          return false if @element_queue.empty?

          next
        end

        is_pop = @current_element.operation == StackEvent::POP

        # The root node only exists in the fragment parser; closing it ends the parse.
        next if @current_element.token.bookmark_name == "root-node"

        if is_pop
          @breadcrumbs.pop
        else
          @breadcrumbs << @current_element.token.node_name
        end

        # Avoid sending close events for elements which don't expect a closing.
        next if is_pop && !expects_closer(@current_element.token)

        return true
      end
    end

    # Legacy: class-wp-html-processor.php:5120.
    def bookmark_token
      @bookmark_counter += 1
      name = @bookmark_counter.to_s
      unless base_class_set_bookmark(name)
        @last_error = ERROR_EXCEEDED_MAX_BOOKMARKS
        raise BookmarkAllocationError, "could not allocate bookmark"
      end

      name
    end

    # One step of the HTML5 tree construction algorithm.
    #
    # BR-MIGRATE-223 / BR-MIGRATE-225. Legacy: class-wp-html-processor.php:1020.
    def step(node_to_process = PROCESS_NEXT_NODE) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      return false unless @last_error.nil?

      if node_to_process != REPROCESS_CURRENT_NODE
        # Void elements are pushed onto the stack so that breadcrumbs and "go to parent"
        # work; when moving on, a void element at the top has to be closed.
        top_node = @state.stack_of_open_elements.current_node
        @state.stack_of_open_elements.pop if top_node && !expects_closer(top_node)
      end

      if node_to_process == PROCESS_NEXT_NODE
        base_class_next_token
        subdivide_text_appropriately if @parser_state == STATE_TEXT_NODE
      end

      return false if @parser_state == STATE_INCOMPLETE_INPUT || @parser_state == STATE_COMPLETE

      adjusted_current_node = get_adjusted_current_node
      is_closer = tag_closer?
      is_start_tag = @parser_state == STATE_MATCHED_TAG && !is_closer
      token_name = get_token_name

      if node_to_process != REPROCESS_CURRENT_NODE
        begin
          bookmark_name = bookmark_token
        rescue BookmarkAllocationError
          return false if @last_error == ERROR_EXCEEDED_MAX_BOOKMARKS

          raise
        end

        @state.current_token = Token.new(bookmark_name, token_name, has_self_closing_flag?)
      end

      parse_in_current_insertion_mode = (
        @state.stack_of_open_elements.count.zero? ||
        adjusted_current_node.namespace == "html" ||
        (
          adjusted_current_node.integration_node_type == "math" &&
          (
            (is_start_tag && !%w[MGLYPH MALIGNMARK].include?(token_name)) ||
            token_name == "#text"
          )
        ) ||
        (
          adjusted_current_node.namespace == "math" &&
          adjusted_current_node.node_name == "ANNOTATION-XML" &&
          is_start_tag && token_name == "SVG"
        ) ||
        (
          adjusted_current_node.integration_node_type == "html" &&
          (is_start_tag || token_name == "#text")
        )
      )

      begin
        return step_in_foreign_content unless parse_in_current_insertion_mode

        dispatch_insertion_mode
      rescue UnsupportedException
        # Exceptions escape deep call stacks; the caller sees `false` plus `last_error`.
        false
      rescue BookmarkAllocationError
        return false if @last_error == ERROR_EXCEEDED_MAX_BOOKMARKS

        raise
      end
    end

    def dispatch_insertion_mode # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
      case @state.insertion_mode
      when ProcessorState::INSERTION_MODE_INITIAL then step_initial
      when ProcessorState::INSERTION_MODE_BEFORE_HTML then step_before_html
      when ProcessorState::INSERTION_MODE_BEFORE_HEAD then step_before_head
      when ProcessorState::INSERTION_MODE_IN_HEAD then step_in_head
      when ProcessorState::INSERTION_MODE_IN_HEAD_NOSCRIPT then step_in_head_noscript
      when ProcessorState::INSERTION_MODE_AFTER_HEAD then step_after_head
      when ProcessorState::INSERTION_MODE_IN_BODY then step_in_body
      when ProcessorState::INSERTION_MODE_IN_TABLE then step_in_table
      when ProcessorState::INSERTION_MODE_IN_TABLE_TEXT then step_in_table_text
      when ProcessorState::INSERTION_MODE_IN_CAPTION then step_in_caption
      when ProcessorState::INSERTION_MODE_IN_COLUMN_GROUP then step_in_column_group
      when ProcessorState::INSERTION_MODE_IN_TABLE_BODY then step_in_table_body
      when ProcessorState::INSERTION_MODE_IN_ROW then step_in_row
      when ProcessorState::INSERTION_MODE_IN_CELL then step_in_cell
      when ProcessorState::INSERTION_MODE_IN_TEMPLATE then step_in_template
      when ProcessorState::INSERTION_MODE_AFTER_BODY then step_after_body
      when ProcessorState::INSERTION_MODE_IN_FRAMESET then step_in_frameset
      when ProcessorState::INSERTION_MODE_AFTER_FRAMESET then step_after_frameset
      when ProcessorState::INSERTION_MODE_AFTER_AFTER_BODY then step_after_after_body
      when ProcessorState::INSERTION_MODE_AFTER_AFTER_FRAMESET then step_after_after_frameset
      else
        bail("Unaware of the requested parsing mode: '#{@state.insertion_mode}'.")
      end
    end

    # The operation sigil used throughout the insertion modes: `+TAG`, `-TAG` or the bare
    # token name for non-tag tokens.
    def current_op
      token_name = get_token_name
      token_type = get_token_type
      op_sigil = token_type == "#tag" ? (base_class_tag_closer? ? "-" : "+") : ""
      ["#{op_sigil}#{token_name}", token_name]
    end

    # Same, but using the tree-aware `tag_closer?`, as the table-ish modes do.
    def current_tag_op
      tag_name = get_tag
      ["#{tag_closer? ? '-' : '+'}#{tag_name}", tag_name]
    end

    # ── Insertion modes ──────────────────────────────────────────────────────────
    #
    # Each of these implements one insertion mode of the HTML5 tree construction
    # algorithm (BR-MIGRATE-223). They are transliterated from the legacy `step_*`
    # methods, which are themselves close transliterations of the specification, so the
    # `case` labels below line up one-for-one with the spec's "A start tag whose tag name
    # is …" clauses.

    # Legacy: class-wp-html-processor.php:1568.
    def step_initial
      op, = current_op

      case op
      when "#text"
        return step if @text_node_classification == TEXT_IS_WHITESPACE
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        insert_html_element(@state.current_token)
        return true
      when "html"
        doctype = get_doctype_info
        @compat_mode = QUIRKS_MODE if doctype && doctype.indicated_compatibility_mode == "quirks"
        @state.insertion_mode = ProcessorState::INSERTION_MODE_BEFORE_HTML
        insert_html_element(@state.current_token)
        return true
      end

      @compat_mode = QUIRKS_MODE
      @state.insertion_mode = ProcessorState::INSERTION_MODE_BEFORE_HTML
      step(REPROCESS_CURRENT_NODE)
    end

    # Legacy: class-wp-html-processor.php:1642.
    def step_before_html
      op, = current_op
      is_closer = base_class_tag_closer?

      case op
      when "html"
        return step
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        insert_html_element(@state.current_token)
        return true
      when "#text"
        return step if @text_node_classification == TEXT_IS_WHITESPACE
      when "+HTML"
        insert_html_element(@state.current_token)
        @state.insertion_mode = ProcessorState::INSERTION_MODE_BEFORE_HEAD
        return true
      when "-HEAD", "-BODY", "-HTML"
        # Fall through to "anything else".
      else
        return step if is_closer
      end

      insert_virtual_node("HTML")
      @state.insertion_mode = ProcessorState::INSERTION_MODE_BEFORE_HEAD
      step(REPROCESS_CURRENT_NODE)
    end

    # Legacy: class-wp-html-processor.php:1742.
    def step_before_head
      op, = current_op
      is_closer = base_class_tag_closer?

      case op
      when "#text"
        return step if @text_node_classification == TEXT_IS_WHITESPACE
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        insert_html_element(@state.current_token)
        return true
      when "html"
        return step
      when "+HTML"
        return step_in_body
      when "+HEAD"
        insert_html_element(@state.current_token)
        @state.head_element = @state.current_token
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_HEAD
        return true
      when "-HEAD", "-BODY", "-HTML"
        # Fall through to "anything else".
      else
        return step if is_closer
      end

      @state.head_element = insert_virtual_node("HEAD")
      @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_HEAD
      step(REPROCESS_CURRENT_NODE)
    end

    # Legacy: class-wp-html-processor.php:1842.
    def step_in_head # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      op, = current_op
      is_closer = base_class_tag_closer?

      case op
      when "#text"
        if @text_node_classification == TEXT_IS_WHITESPACE
          insert_html_element(@state.current_token)
          return true
        end
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        insert_html_element(@state.current_token)
        return true
      when "html"
        return step
      when "+HTML"
        return step_in_body
      when "+BASE", "+BASEFONT", "+BGSOUND", "+LINK", "+TITLE", "+NOFRAMES", "+STYLE", "+SCRIPT"
        insert_html_element(@state.current_token)
        return true
      when "+META"
        insert_html_element(@state.current_token)
        return true if @state.encoding_confidence != "tentative"

        charset = get_attribute("charset")
        bail("Cannot yet process META tags with charset to determine encoding.") if charset.is_a?(String)

        http_equiv = get_attribute("http-equiv")
        content = get_attribute("content")
        if http_equiv.is_a?(String) && content.is_a?(String) && http_equiv.casecmp("Content-Type").zero?
          bail("Cannot yet process META tags with http-equiv Content-Type to determine encoding.")
        end
        return true
      when "+NOSCRIPT"
        insert_html_element(@state.current_token)
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_HEAD_NOSCRIPT
        return true
      when "-HEAD"
        @state.stack_of_open_elements.pop
        @state.insertion_mode = ProcessorState::INSERTION_MODE_AFTER_HEAD
        return true
      when "-BODY", "-HTML"
        # Fall through to "anything else".
      when "+TEMPLATE"
        @state.active_formatting_elements.insert_marker
        @state.frameset_ok = false
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TEMPLATE
        @state.stack_of_template_insertion_modes << ProcessorState::INSERTION_MODE_IN_TEMPLATE
        insert_html_element(@state.current_token)
        return true
      when "-TEMPLATE"
        return step unless @state.stack_of_open_elements.contains?("TEMPLATE")

        generate_implied_end_tags_thoroughly
        @state.stack_of_open_elements.pop_until("TEMPLATE")
        @state.active_formatting_elements.clear_up_to_last_marker
        @state.stack_of_template_insertion_modes.pop
        reset_insertion_mode_appropriately
        return true
      else
        return step if op == "+HEAD" || is_closer
      end

      @state.stack_of_open_elements.pop
      @state.insertion_mode = ProcessorState::INSERTION_MODE_AFTER_HEAD
      step(REPROCESS_CURRENT_NODE)
    end

    # Legacy: class-wp-html-processor.php:2067.
    def step_in_head_noscript
      op, = current_op
      is_closer = base_class_tag_closer?

      case op
      when "#text"
        return step_in_head if @text_node_classification == TEXT_IS_WHITESPACE
      when "html"
        return step
      when "+HTML"
        return step_in_body
      when "-NOSCRIPT"
        @state.stack_of_open_elements.pop
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_HEAD
        return true
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction",
           "+BASEFONT", "+BGSOUND", "+LINK", "+META", "+NOFRAMES", "+STYLE"
        return step_in_head
      else
        return step if op == "+HEAD" || op == "+NOSCRIPT" || is_closer
      end

      @state.stack_of_open_elements.pop
      @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_HEAD
      step(REPROCESS_CURRENT_NODE)
    end

    # Legacy: class-wp-html-processor.php:2172.
    def step_after_head
      op, = current_op
      is_closer = base_class_tag_closer?

      case op
      when "#text"
        if @text_node_classification == TEXT_IS_WHITESPACE
          insert_html_element(@state.current_token)
          return true
        end
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        insert_html_element(@state.current_token)
        return true
      when "html"
        return step
      when "+HTML"
        return step_in_body
      when "+BODY"
        insert_html_element(@state.current_token)
        @state.frameset_ok = false
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_BODY
        return true
      when "+FRAMESET"
        insert_html_element(@state.current_token)
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_FRAMESET
        return true
      when "+BASE", "+BASEFONT", "+BGSOUND", "+LINK", "+META", "+NOFRAMES", "+SCRIPT",
           "+STYLE", "+TEMPLATE", "+TITLE"
        bail("Cannot process elements after HEAD which reopen the HEAD element.")
      when "-TEMPLATE"
        return step_in_head
      when "-BODY", "-HTML"
        # Fall through to "anything else".
      else
        return step if op == "+HEAD" || is_closer
      end

      insert_virtual_node("BODY")
      @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_BODY
      step(REPROCESS_CURRENT_NODE)
    end

    # The `in body` insertion mode: the bulk of HTML tree construction.
    #
    # BR-MIGRATE-223. Legacy: class-wp-html-processor.php:2319.
    def step_in_body # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
      op, token_name = current_op

      case op
      when "#text"
        return step if @text_node_classification == TEXT_IS_NULL_SEQUENCE

        reconstruct_active_formatting_elements
        @state.frameset_ok = false if @text_node_classification == TEXT_IS_GENERIC
        insert_html_element(@state.current_token)
        return true
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        insert_html_element(@state.current_token)
        return true
      when "html", "+HTML"
        return step
      when "+BASE", "+BASEFONT", "+BGSOUND", "+LINK", "+META", "+NOFRAMES", "+SCRIPT",
           "+STYLE", "+TEMPLATE", "+TITLE", "-TEMPLATE"
        return step_in_head
      when "+BODY"
        if @state.stack_of_open_elements.count != 1 &&
           @state.stack_of_open_elements.at(2)&.node_name == "BODY" &&
           !@state.stack_of_open_elements.contains?("TEMPLATE")
          @state.frameset_ok = false
        end
        return step
      when "+FRAMESET"
        if @state.stack_of_open_elements.count == 1 ||
           @state.stack_of_open_elements.at(2)&.node_name != "BODY" ||
           @state.frameset_ok == false
          return step
        end

        bail("Cannot process non-ignored FRAMESET tags.")
      when "-BODY"
        return step unless @state.stack_of_open_elements.has_element_in_scope?("BODY")

        @state.insertion_mode = ProcessorState::INSERTION_MODE_AFTER_BODY
        return step
      when "-HTML"
        return step unless @state.stack_of_open_elements.has_element_in_scope?("BODY")

        @state.insertion_mode = ProcessorState::INSERTION_MODE_AFTER_BODY
        return step(REPROCESS_CURRENT_NODE)
      when "+ADDRESS", "+ARTICLE", "+ASIDE", "+BLOCKQUOTE", "+CENTER", "+DETAILS", "+DIALOG",
           "+DIR", "+DIV", "+DL", "+FIELDSET", "+FIGCAPTION", "+FIGURE", "+FOOTER", "+HEADER",
           "+HGROUP", "+MAIN", "+MENU", "+NAV", "+OL", "+P", "+SEARCH", "+SECTION", "+SUMMARY",
           "+UL"
        close_a_p_element if @state.stack_of_open_elements.has_p_in_button_scope?
        insert_html_element(@state.current_token)
        return true
      when "+H1", "+H2", "+H3", "+H4", "+H5", "+H6"
        close_a_p_element if @state.stack_of_open_elements.has_p_in_button_scope?
        if HEADINGS.include?(@state.stack_of_open_elements.current_node.node_name)
          @state.stack_of_open_elements.pop
        end
        insert_html_element(@state.current_token)
        return true
      when "+PRE", "+LISTING"
        close_a_p_element if @state.stack_of_open_elements.has_p_in_button_scope?
        insert_html_element(@state.current_token)
        @state.frameset_ok = false
        return true
      when "+FORM"
        stack_contains_template = @state.stack_of_open_elements.contains?("TEMPLATE")
        return step if @state.form_element && !stack_contains_template

        close_a_p_element if @state.stack_of_open_elements.has_p_in_button_scope?
        insert_html_element(@state.current_token)
        @state.form_element = @state.current_token unless stack_contains_template
        return true
      when "+DD", "+DT", "+LI"
        return step_in_body_list_item(token_name)
      when "+PLAINTEXT"
        close_a_p_element if @state.stack_of_open_elements.has_p_in_button_scope?
        bail("Cannot process PLAINTEXT elements.")
      when "+BUTTON"
        if @state.stack_of_open_elements.has_element_in_scope?("BUTTON")
          generate_implied_end_tags
          @state.stack_of_open_elements.pop_until("BUTTON")
        end
        reconstruct_active_formatting_elements
        insert_html_element(@state.current_token)
        @state.frameset_ok = false
        return true
      when "-ADDRESS", "-ARTICLE", "-ASIDE", "-BLOCKQUOTE", "-BUTTON", "-CENTER", "-DETAILS",
           "-DIALOG", "-DIR", "-DIV", "-DL", "-FIELDSET", "-FIGCAPTION", "-FIGURE", "-FOOTER",
           "-HEADER", "-HGROUP", "-LISTING", "-MAIN", "-MENU", "-NAV", "-OL", "-PRE",
           "-SEARCH", "-SECTION", "-SELECT", "-SUMMARY", "-UL"
        return step unless @state.stack_of_open_elements.has_element_in_scope?(token_name)

        generate_implied_end_tags
        @state.stack_of_open_elements.pop_until(token_name)
        return true
      when "-FORM"
        return step_in_body_end_form
      when "-P"
        insert_html_element(@state.current_token) unless @state.stack_of_open_elements.has_p_in_button_scope?
        close_a_p_element
        return true
      when "-DD", "-DT", "-LI"
        if (token_name == "LI" && !@state.stack_of_open_elements.has_element_in_list_item_scope?("LI")) ||
           (token_name != "LI" && !@state.stack_of_open_elements.has_element_in_scope?(token_name))
          return step
        end

        generate_implied_end_tags(token_name)
        @state.stack_of_open_elements.pop_until(token_name)
        return true
      when "-H1", "-H2", "-H3", "-H4", "-H5", "-H6"
        unless @state.stack_of_open_elements.has_element_in_scope?(OpenElements::H1_THROUGH_H6)
          return step
        end

        generate_implied_end_tags
        @state.stack_of_open_elements.pop_until(OpenElements::H1_THROUGH_H6)
        return true
      when "+A"
        @state.active_formatting_elements.walk_up do |item|
          break if item.node_name == ActiveFormattingElements::MARKER

          next unless item.node_name == "A"

          run_adoption_agency_algorithm
          @state.active_formatting_elements.remove_node(item)
          @state.stack_of_open_elements.remove_node(item)
          break
        end
        reconstruct_active_formatting_elements
        insert_html_element(@state.current_token)
        @state.active_formatting_elements.push(@state.current_token)
        return true
      when "+B", "+BIG", "+CODE", "+EM", "+FONT", "+I", "+S", "+SMALL", "+STRIKE", "+STRONG",
           "+TT", "+U"
        reconstruct_active_formatting_elements
        insert_html_element(@state.current_token)
        @state.active_formatting_elements.push(@state.current_token)
        return true
      when "+NOBR"
        reconstruct_active_formatting_elements
        if @state.stack_of_open_elements.has_element_in_scope?("NOBR")
          run_adoption_agency_algorithm
          reconstruct_active_formatting_elements
        end
        insert_html_element(@state.current_token)
        @state.active_formatting_elements.push(@state.current_token)
        return true
      when "-A", "-B", "-BIG", "-CODE", "-EM", "-FONT", "-I", "-NOBR", "-S", "-SMALL",
           "-STRIKE", "-STRONG", "-TT", "-U"
        run_adoption_agency_algorithm
        return true
      when "+APPLET", "+MARQUEE", "+OBJECT"
        reconstruct_active_formatting_elements
        insert_html_element(@state.current_token)
        @state.active_formatting_elements.insert_marker
        @state.frameset_ok = false
        return true
      when "-APPLET", "-MARQUEE", "-OBJECT"
        return step unless @state.stack_of_open_elements.has_element_in_scope?(token_name)

        generate_implied_end_tags
        @state.stack_of_open_elements.pop_until(token_name)
        @state.active_formatting_elements.clear_up_to_last_marker
        return true
      when "+TABLE"
        if @compat_mode != QUIRKS_MODE && @state.stack_of_open_elements.has_p_in_button_scope?
          close_a_p_element
        end
        insert_html_element(@state.current_token)
        @state.frameset_ok = false
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE
        return true
      when "+AREA", "+BR", "+EMBED", "+IMG", "+KEYGEN", "+WBR"
        reconstruct_active_formatting_elements
        insert_html_element(@state.current_token)
        @state.frameset_ok = false
        return true
      when "+INPUT"
        return step if @context_node && @context_node.node_name == "SELECT"

        if @state.stack_of_open_elements.has_element_in_scope?("SELECT")
          @state.stack_of_open_elements.pop_until("SELECT")
        end
        reconstruct_active_formatting_elements
        insert_html_element(@state.current_token)
        type_attribute = get_attribute("type")
        unless type_attribute.is_a?(String) && type_attribute.downcase == "hidden"
          @state.frameset_ok = false
        end
        return true
      when "+PARAM", "+SOURCE", "+TRACK"
        insert_html_element(@state.current_token)
        return true
      when "+HR"
        close_a_p_element if @state.stack_of_open_elements.has_p_in_button_scope?
        generate_implied_end_tags if @state.stack_of_open_elements.has_element_in_scope?("SELECT")
        insert_html_element(@state.current_token)
        @state.frameset_ok = false
        return true
      when "+IMAGE"
        bail("Cannot process an IMAGE tag. (Don't ask.)")
      when "+TEXTAREA"
        insert_html_element(@state.current_token)
        @state.frameset_ok = false
        return true
      when "+XMP"
        close_a_p_element if @state.stack_of_open_elements.has_p_in_button_scope?
        reconstruct_active_formatting_elements
        @state.frameset_ok = false
        insert_html_element(@state.current_token)
        return true
      when "+IFRAME"
        @state.frameset_ok = false
        insert_html_element(@state.current_token)
        return true
      when "+NOEMBED"
        insert_html_element(@state.current_token)
        return true
      when "+SELECT"
        return step if @context_node && @context_node.node_name == "SELECT"

        if @state.stack_of_open_elements.has_element_in_scope?("SELECT")
          @state.stack_of_open_elements.pop_until("SELECT")
          return step
        end
        reconstruct_active_formatting_elements
        insert_html_element(@state.current_token)
        @state.frameset_ok = false
        return true
      when "+OPTION"
        if @state.stack_of_open_elements.has_element_in_scope?("SELECT")
          generate_implied_end_tags("OPTGROUP")
        elsif @state.stack_of_open_elements.current_node_is?("OPTION")
          @state.stack_of_open_elements.pop
        end
        reconstruct_active_formatting_elements
        insert_html_element(@state.current_token)
        return true
      when "+OPTGROUP"
        if @state.stack_of_open_elements.has_element_in_scope?("SELECT")
          generate_implied_end_tags
        elsif @state.stack_of_open_elements.current_node_is?("OPTION")
          @state.stack_of_open_elements.pop
        end
        reconstruct_active_formatting_elements
        insert_html_element(@state.current_token)
        return true
      when "+RB", "+RTC"
        generate_implied_end_tags if @state.stack_of_open_elements.has_element_in_scope?("RUBY")
        insert_html_element(@state.current_token)
        return true
      when "+RP", "+RT"
        generate_implied_end_tags("RTC") if @state.stack_of_open_elements.has_element_in_scope?("RUBY")
        insert_html_element(@state.current_token)
        return true
      when "+MATH", "+SVG"
        reconstruct_active_formatting_elements
        @state.current_token.namespace = op == "+MATH" ? "math" : "svg"
        insert_html_element(@state.current_token)
        @state.stack_of_open_elements.pop if @state.current_token.has_self_closing_flag
        return true
      when "+CAPTION", "+COL", "+COLGROUP", "+FRAME", "+HEAD", "+TBODY", "+TD", "+TFOOT",
           "+TH", "+THEAD", "+TR"
        return step
      end

      if base_class_tag_closer?
        in_body_any_other_end_tag
      else
        reconstruct_active_formatting_elements
        insert_html_element(@state.current_token)
        true
      end
    end

    # `DD`, `DT` and `LI` close a previous list item of the same kind before opening.
    # Legacy: class-wp-html-processor.php:2469.
    def step_in_body_list_item(token_name)
      @state.frameset_ok = false
      node = @state.stack_of_open_elements.current_node
      is_li = token_name == "LI"

      loop do
        matches = is_li ? node.node_name == "LI" : %w[DD DT].include?(node.node_name)
        if matches
          name = is_li ? "LI" : node.node_name
          generate_implied_end_tags(name)
          @state.stack_of_open_elements.pop_until(name)
          break
        end

        break if !%w[ADDRESS DIV P].include?(node.node_name) && self.class.special?(node)

        next_node = nil
        @state.stack_of_open_elements.walk_up(node) do |item|
          next_node = item
          break
        end
        break if next_node.nil?

        node = next_node
      end

      close_a_p_element if @state.stack_of_open_elements.has_p_in_button_scope?
      insert_html_element(@state.current_token)
      true
    end

    # Legacy: class-wp-html-processor.php:2760.
    def step_in_body_end_form
      unless @state.stack_of_open_elements.contains?("TEMPLATE")
        node = @state.form_element
        return step if node.nil? || !@state.stack_of_open_elements.has_element_in_scope?("FORM")

        @state.form_element = nil
        generate_implied_end_tags
        unless node.equal?(@state.stack_of_open_elements.current_node)
          bail("Cannot close a FORM when other elements remain open as this would throw off the breadcrumbs for the following tokens.")
        end
        @state.stack_of_open_elements.remove_node(node)
        return true
      end

      return step unless @state.stack_of_open_elements.has_element_in_scope?("FORM")

      generate_implied_end_tags
      @state.stack_of_open_elements.pop_until("FORM")
      true
    end

    # Legacy: class-wp-html-processor.php:3387.
    def in_body_any_other_end_tag
      token_name = get_token_name
      node = nil

      @state.stack_of_open_elements.walk_up do |candidate|
        node = candidate
        break if node.namespace == "html" && token_name == node.node_name

        return step if self.class.special?(node)
      end

      return step if node.nil?

      generate_implied_end_tags(token_name)

      @state.stack_of_open_elements.walk_up do |item|
        @state.stack_of_open_elements.pop
        return true if node.equal?(item)
      end

      bail('Should not have been able to reach end of "any other end tag" IN BODY processing. Check HTML API code.')
    end

    # Legacy: class-wp-html-processor.php:3440.
    def step_in_table # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      op, = current_op

      case op
      when "#text"
        current_node = @state.stack_of_open_elements.current_node
        current_node_name = current_node&.node_name
        if current_node_name &&
           %w[TABLE TBODY TEMPLATE TFOOT THEAD TR].include?(current_node_name)
          return step if @text_node_classification == TEXT_IS_NULL_SEQUENCE

          if @text_node_classification == TEXT_IS_WHITESPACE
            insert_html_element(@state.current_token)
            return true
          end
        end
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        insert_html_element(@state.current_token)
        return true
      when "html"
        return step
      when "+CAPTION"
        @state.stack_of_open_elements.clear_to_table_context
        @state.active_formatting_elements.insert_marker
        insert_html_element(@state.current_token)
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_CAPTION
        return true
      when "+COLGROUP"
        @state.stack_of_open_elements.clear_to_table_context
        insert_html_element(@state.current_token)
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_COLUMN_GROUP
        return true
      when "+COL"
        @state.stack_of_open_elements.clear_to_table_context
        insert_virtual_node("COLGROUP")
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_COLUMN_GROUP
        return step(REPROCESS_CURRENT_NODE)
      when "+TBODY", "+TFOOT", "+THEAD"
        @state.stack_of_open_elements.clear_to_table_context
        insert_html_element(@state.current_token)
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE_BODY
        return true
      when "+TD", "+TH", "+TR"
        @state.stack_of_open_elements.clear_to_table_context
        insert_virtual_node("TBODY")
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE_BODY
        return step(REPROCESS_CURRENT_NODE)
      when "+TABLE"
        return step unless @state.stack_of_open_elements.has_element_in_table_scope?("TABLE")

        @state.stack_of_open_elements.pop_until("TABLE")
        reset_insertion_mode_appropriately
        return step(REPROCESS_CURRENT_NODE)
      when "-TABLE"
        return step unless @state.stack_of_open_elements.has_element_in_table_scope?("TABLE")

        @state.stack_of_open_elements.pop_until("TABLE")
        reset_insertion_mode_appropriately
        return true
      when "-BODY", "-CAPTION", "-COL", "-COLGROUP", "-HTML", "-TBODY", "-TD", "-TFOOT",
           "-TH", "-THEAD", "-TR"
        return step
      when "+STYLE", "+SCRIPT", "+TEMPLATE", "-TEMPLATE"
        return step_in_head
      when "+INPUT"
        type_attribute = get_attribute("type")
        if type_attribute.is_a?(String) && type_attribute.downcase == "hidden"
          insert_html_element(@state.current_token)
          return true
        end
      when "+FORM"
        if @state.stack_of_open_elements.has_element_in_scope?("TEMPLATE") || @state.form_element
          return step
        end

        insert_html_element(@state.current_token)
        @state.form_element = @state.current_token
        @state.stack_of_open_elements.pop
        return true
      end

      # Anything else would require foster parenting, which the HTML API does not do.
      bail("Foster parenting is not supported.")
    end

    # Legacy: class-wp-html-processor.php:3699.
    def step_in_table_text
      bail("No support for parsing in the #{ProcessorState::INSERTION_MODE_IN_TABLE_TEXT} state.")
    end

    # Legacy: class-wp-html-processor.php:3719.
    def step_in_caption
      op, = current_tag_op

      case op
      when "-CAPTION", "+CAPTION", "+COL", "+COLGROUP", "+TBODY", "+TD", "+TFOOT", "+TH",
           "+THEAD", "+TR", "-TABLE"
        return step unless @state.stack_of_open_elements.has_element_in_table_scope?("CAPTION")

        generate_implied_end_tags
        @state.stack_of_open_elements.pop_until("CAPTION")
        @state.active_formatting_elements.clear_up_to_last_marker
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE
        return true if op == "-CAPTION"

        step(REPROCESS_CURRENT_NODE)
      when "-BODY", "-COL", "-COLGROUP", "-HTML", "-TBODY", "-TD", "-TFOOT", "-TH", "-THEAD",
           "-TR"
        step
      else
        step_in_body
      end
    end

    # Legacy: class-wp-html-processor.php:3804.
    def step_in_column_group
      op, = current_op

      case op
      when "#text"
        if @text_node_classification == TEXT_IS_WHITESPACE
          insert_html_element(@state.current_token)
          return true
        end
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        insert_html_element(@state.current_token)
        return true
      when "html"
        return step
      when "+HTML"
        return step_in_body
      when "+COL"
        insert_html_element(@state.current_token)
        @state.stack_of_open_elements.pop
        return true
      when "-COLGROUP"
        return step unless @state.stack_of_open_elements.current_node_is?("COLGROUP")

        @state.stack_of_open_elements.pop
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE
        return true
      when "-COL"
        return step
      when "+TEMPLATE", "-TEMPLATE"
        return step_in_head
      end

      return step unless @state.stack_of_open_elements.current_node_is?("COLGROUP")

      @state.stack_of_open_elements.pop
      @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE
      step(REPROCESS_CURRENT_NODE)
    end

    # Legacy: class-wp-html-processor.php:3914.
    def step_in_table_body
      op, tag_name = current_tag_op

      case op
      when "+TR"
        @state.stack_of_open_elements.clear_to_table_body_context
        insert_html_element(@state.current_token)
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_ROW
        true
      when "+TH", "+TD"
        @state.stack_of_open_elements.clear_to_table_body_context
        insert_virtual_node("TR")
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_ROW
        step(REPROCESS_CURRENT_NODE)
      when "-TBODY", "-TFOOT", "-THEAD"
        return step unless @state.stack_of_open_elements.has_element_in_table_scope?(tag_name)

        @state.stack_of_open_elements.clear_to_table_body_context
        @state.stack_of_open_elements.pop
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE
        true
      when "+CAPTION", "+COL", "+COLGROUP", "+TBODY", "+TFOOT", "+THEAD", "-TABLE"
        if !@state.stack_of_open_elements.has_element_in_table_scope?("TBODY") &&
           !@state.stack_of_open_elements.has_element_in_table_scope?("THEAD") &&
           !@state.stack_of_open_elements.has_element_in_table_scope?("TFOOT")
          return step
        end

        @state.stack_of_open_elements.clear_to_table_body_context
        @state.stack_of_open_elements.pop
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE
        step(REPROCESS_CURRENT_NODE)
      when "-BODY", "-CAPTION", "-COL", "-COLGROUP", "-HTML", "-TD", "-TH", "-TR"
        step
      else
        step_in_table
      end
    end

    # Legacy: class-wp-html-processor.php:4018.
    def step_in_row
      op, tag_name = current_tag_op

      case op
      when "+TH", "+TD"
        @state.stack_of_open_elements.clear_to_table_row_context
        insert_html_element(@state.current_token)
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_CELL
        @state.active_formatting_elements.insert_marker
        true
      when "-TR"
        return step unless @state.stack_of_open_elements.has_element_in_table_scope?("TR")

        @state.stack_of_open_elements.clear_to_table_row_context
        @state.stack_of_open_elements.pop
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE_BODY
        true
      when "+CAPTION", "+COL", "+COLGROUP", "+TBODY", "+TFOOT", "+THEAD", "+TR", "-TABLE"
        return step unless @state.stack_of_open_elements.has_element_in_table_scope?("TR")

        @state.stack_of_open_elements.clear_to_table_row_context
        @state.stack_of_open_elements.pop
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE_BODY
        step(REPROCESS_CURRENT_NODE)
      when "-TBODY", "-TFOOT", "-THEAD"
        return step unless @state.stack_of_open_elements.has_element_in_table_scope?(tag_name)
        return step unless @state.stack_of_open_elements.has_element_in_table_scope?("TR")

        @state.stack_of_open_elements.clear_to_table_row_context
        @state.stack_of_open_elements.pop
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE_BODY
        step(REPROCESS_CURRENT_NODE)
      when "-BODY", "-CAPTION", "-COL", "-COLGROUP", "-HTML", "-TD", "-TH"
        step
      else
        step_in_table
      end
    end

    # Legacy: class-wp-html-processor.php:4129.
    def step_in_cell
      op, tag_name = current_tag_op

      case op
      when "-TD", "-TH"
        return step unless @state.stack_of_open_elements.has_element_in_table_scope?(tag_name)

        generate_implied_end_tags
        @state.stack_of_open_elements.pop_until(tag_name)
        @state.active_formatting_elements.clear_up_to_last_marker
        @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_ROW
        true
      when "+CAPTION", "+COL", "+COLGROUP", "+TBODY", "+TD", "+TFOOT", "+TH", "+THEAD", "+TR"
        close_cell
        step(REPROCESS_CURRENT_NODE)
      when "-BODY", "-CAPTION", "-COL", "-COLGROUP", "-HTML"
        step
      when "-TABLE", "-TBODY", "-TFOOT", "-THEAD", "-TR"
        return step unless @state.stack_of_open_elements.has_element_in_table_scope?(tag_name)

        close_cell
        step(REPROCESS_CURRENT_NODE)
      else
        step_in_body
      end
    end

    # Legacy: class-wp-html-processor.php:4234.
    def step_in_template
      op, = current_op
      is_closer = tag_closer?

      case op
      when "#text", "#comment", "#funky-comment", "#presumptuous-tag",
           "#processing-instruction", "html"
        return step_in_body
      when "+BASE", "+BASEFONT", "+BGSOUND", "+LINK", "+META", "+NOFRAMES", "+SCRIPT",
           "+STYLE", "+TEMPLATE", "+TITLE", "-TEMPLATE"
        return step_in_head
      when "+CAPTION", "+COLGROUP", "+TBODY", "+TFOOT", "+THEAD"
        return switch_template_insertion_mode(ProcessorState::INSERTION_MODE_IN_TABLE)
      when "+COL"
        return switch_template_insertion_mode(ProcessorState::INSERTION_MODE_IN_COLUMN_GROUP)
      when "+TR"
        return switch_template_insertion_mode(ProcessorState::INSERTION_MODE_IN_TABLE_BODY)
      when "+TD", "+TH"
        return switch_template_insertion_mode(ProcessorState::INSERTION_MODE_IN_ROW)
      end

      return switch_template_insertion_mode(ProcessorState::INSERTION_MODE_IN_BODY) unless is_closer

      step
    end

    def switch_template_insertion_mode(mode)
      @state.stack_of_template_insertion_modes.pop
      @state.stack_of_template_insertion_modes << mode
      @state.insertion_mode = mode
      step(REPROCESS_CURRENT_NODE)
    end

    # Legacy: class-wp-html-processor.php:4366.
    def step_after_body
      op, = current_op

      case op
      when "#text"
        return step_in_body if @text_node_classification == TEXT_IS_WHITESPACE
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        bail("Content outside of BODY is unsupported.")
      when "html"
        return step
      when "+HTML"
        return step_in_body
      when "-HTML"
        return step if @context_node

        @state.insertion_mode = ProcessorState::INSERTION_MODE_AFTER_AFTER_BODY
        return step
      end

      @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_BODY
      step(REPROCESS_CURRENT_NODE)
    end

    # Legacy: class-wp-html-processor.php:4458.
    def step_in_frameset
      op, = current_op

      case op
      when "#text"
        return step_in_body if @text_node_classification == TEXT_IS_WHITESPACE

        bail("Non-whitespace characters cannot be handled in frameset.")
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        insert_html_element(@state.current_token)
        true
      when "html"
        step
      when "+HTML"
        step_in_body
      when "+FRAMESET"
        insert_html_element(@state.current_token)
        true
      when "-FRAMESET"
        return step if @state.stack_of_open_elements.current_node_is?("HTML")

        @state.stack_of_open_elements.pop
        if @context_node.nil? && !@state.stack_of_open_elements.current_node_is?("FRAMESET")
          @state.insertion_mode = ProcessorState::INSERTION_MODE_AFTER_FRAMESET
        end
        true
      when "+FRAME"
        insert_html_element(@state.current_token)
        @state.stack_of_open_elements.pop
        true
      when "+NOFRAMES"
        step_in_head
      else
        step
      end
    end

    # Legacy: class-wp-html-processor.php:4580.
    def step_after_frameset
      op, = current_op

      case op
      when "#text"
        return step_in_body if @text_node_classification == TEXT_IS_WHITESPACE

        bail("Non-whitespace characters cannot be handled in after frameset")
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        insert_html_element(@state.current_token)
        true
      when "html"
        step
      when "+HTML"
        step_in_body
      when "-HTML"
        @state.insertion_mode = ProcessorState::INSERTION_MODE_AFTER_AFTER_FRAMESET
        step
      when "+NOFRAMES"
        step_in_head
      else
        step
      end
    end

    # Legacy: class-wp-html-processor.php:4668.
    def step_after_after_body
      op, = current_op

      case op
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        bail("Content outside of HTML is unsupported.")
      when "html", "+HTML"
        return step_in_body
      when "#text"
        return step_in_body if @text_node_classification == TEXT_IS_WHITESPACE
      end

      @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_BODY
      step(REPROCESS_CURRENT_NODE)
    end

    # Legacy: class-wp-html-processor.php:4734.
    def step_after_after_frameset
      op, = current_op

      case op
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        bail("Content outside of HTML is unsupported.")
      when "html", "+HTML"
        step_in_body
      when "#text"
        return step_in_body if @text_node_classification == TEXT_IS_WHITESPACE

        bail("Non-whitespace characters cannot be handled in after after frameset.")
      when "+NOFRAMES"
        step_in_head
      else
        step
      end
    end

    # Legacy: class-wp-html-processor.php:4805.
    def step_in_foreign_content # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      op, tag_name = current_op

      if op == "+FONT" &&
         (!get_attribute("color").nil? || !get_attribute("face").nil? || !get_attribute("size").nil?)
        op = "+FONT with attributes"
      end

      case op
      when "#text"
        @state.frameset_ok = false if @text_node_classification == TEXT_IS_GENERIC
        insert_foreign_element(@state.current_token, false)
        return true
      when "#cdata-section"
        current_token = @bookmarks[@state.current_token.bookmark_name]
        cdata_content_start = current_token.start + 9
        cdata_content_length = current_token.length - 12
        if ByteScan.span(@html, "\x00 \t\n\f\r", cdata_content_start, cdata_content_length) !=
           cdata_content_length
          @state.frameset_ok = false
        end
        insert_foreign_element(@state.current_token, false)
        return true
      when "#comment", "#funky-comment", "#presumptuous-tag", "#processing-instruction"
        insert_foreign_element(@state.current_token, false)
        return true
      when "html"
        return step
      when "+B", "+BIG", "+BLOCKQUOTE", "+BODY", "+BR", "+CENTER", "+CODE", "+DD", "+DIV",
           "+DL", "+DT", "+EM", "+EMBED", "+H1", "+H2", "+H3", "+H4", "+H5", "+H6", "+HEAD",
           "+HR", "+I", "+IMG", "+LI", "+LISTING", "+MENU", "+META", "+NOBR", "+OL", "+P",
           "+PRE", "+RUBY", "+S", "+SMALL", "+SPAN", "+STRONG", "+STRIKE", "+SUB", "+SUP",
           "+TABLE", "+TT", "+U", "+UL", "+VAR", "+FONT with attributes", "-BR", "-P"
        @state.stack_of_open_elements.walk_up do |current_node|
          if current_node.integration_node_type == "math" ||
             current_node.integration_node_type == "html" ||
             current_node.namespace == "html"
            break
          end

          @state.stack_of_open_elements.pop
        end
        return dispatch_insertion_mode
      end

      unless tag_closer?
        insert_foreign_element(@state.current_token, false)
        @state.stack_of_open_elements.pop if @state.current_token.has_self_closing_flag
        return true
      end

      if @state.current_token.node_name == "SCRIPT" && @state.current_token.namespace == "svg"
        @state.stack_of_open_elements.pop
        return true
      end

      node = @state.stack_of_open_elements.current_node
      loop do
        return true if node.equal?(@state.stack_of_open_elements.at(1))

        if node.node_name.casecmp(tag_name).zero?
          @state.stack_of_open_elements.walk_up do |item|
            @state.stack_of_open_elements.pop
            return true if node.equal?(item)
          end
        end

        next_node = nil
        @state.stack_of_open_elements.walk_up(node) do |item|
          next_node = item
          break
        end
        break if next_node.nil?

        node = next_node
        break if node.namespace == "html"
      end

      dispatch_insertion_mode
    end

    # ── Tree construction helpers ────────────────────────────────────────────────

    # Legacy: class-wp-html-processor.php:5787.
    def close_a_p_element
      generate_implied_end_tags("P")
      @state.stack_of_open_elements.pop_until("P")
    end

    # Legacy: class-wp-html-processor.php:5803.
    def generate_implied_end_tags(except_for_this_element = nil)
      no_exclusions = except_for_this_element.nil?

      while (no_exclusions || !@state.stack_of_open_elements.current_node_is?(except_for_this_element)) &&
            ELEMENTS_WITH_IMPLIED_END_TAGS.include?(@state.stack_of_open_elements.current_node&.node_name)
        @state.stack_of_open_elements.pop
      end
    end

    # Legacy: class-wp-html-processor.php:5840.
    def generate_implied_end_tags_thoroughly
      while ELEMENTS_WITH_IMPLIED_END_TAGS_THOROUGHLY.include?(
        @state.stack_of_open_elements.current_node&.node_name
      )
        @state.stack_of_open_elements.pop
      end
    end

    # BR-MIGRATE-224 — in a fragment parser the context element stands in for the missing
    # ancestor chain once the stack has been unwound to the root.
    # Legacy: class-wp-html-processor.php:5882.
    def get_adjusted_current_node
      return @context_node if @context_node && @state.stack_of_open_elements.count == 1

      @state.stack_of_open_elements.current_node
    end

    # BR-MIGRATE-225 — reconstructing formatting elements requires re-emitting tokens that
    # were already visited, which a forward-only processor cannot do; the legacy therefore
    # refuses rather than producing a tree with the wrong shape.
    # Legacy: class-wp-html-processor.php:5906.
    def reconstruct_active_formatting_elements
      return false if @state.active_formatting_elements.count.zero?

      last_entry = @state.active_formatting_elements.current_node
      if last_entry.node_name == ActiveFormattingElements::MARKER ||
         @state.stack_of_open_elements.contains_node?(last_entry)
        return false
      end

      bail("Cannot reconstruct active formatting elements when advancing and rewinding is required.")
    end

    # Legacy: class-wp-html-processor.php:5945.
    def reset_insertion_mode_appropriately # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      first_node = @state.stack_of_open_elements.stack.first
      last = false

      @state.stack_of_open_elements.walk_up do |item|
        node = item
        if node.equal?(first_node)
          last = true
          node = @context_node if @context_node
        end

        next if node.namespace != "html"

        case node.node_name
        when "TD", "TH"
          unless last
            @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_CELL
            return
          end
        when "TR"
          @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_ROW
          return
        when "TBODY", "THEAD", "TFOOT"
          @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE_BODY
          return
        when "CAPTION"
          @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_CAPTION
          return
        when "COLGROUP"
          @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_COLUMN_GROUP
          return
        when "TABLE"
          @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_TABLE
          return
        when "TEMPLATE"
          @state.insertion_mode = @state.stack_of_template_insertion_modes.last
          return
        when "HEAD"
          unless last
            @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_HEAD
            return
          end
        when "BODY"
          @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_BODY
          return
        when "FRAMESET"
          @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_FRAMESET
          return
        when "HTML"
          @state.insertion_mode = if @state.head_element
                                    ProcessorState::INSERTION_MODE_AFTER_HEAD
                                  else
                                    ProcessorState::INSERTION_MODE_BEFORE_HEAD
                                  end
          return
        end
      end

      @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_BODY
    end

    # The adoption agency algorithm, as far as a forward-only processor can take it.
    #
    # BR-MIGRATE-223 / BR-MIGRATE-225 — the cases that only require closing elements are
    # handled; the cases that would require re-parenting already-emitted content bail,
    # because re-parenting is exactly what a processor with no tree cannot do.
    # Legacy: class-wp-html-processor.php:6101.
    def run_adoption_agency_algorithm # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      budget = 1000
      subject = get_tag
      current_node = @state.stack_of_open_elements.current_node

      if current_node && subject == current_node.node_name &&
         !@state.active_formatting_elements.contains_node?(current_node)
        @state.stack_of_open_elements.pop
        return
      end

      outer_loop_counter = 0
      while budget.positive?
        budget -= 1
        return if outer_loop_counter >= 8

        outer_loop_counter += 1

        formatting_element = nil
        @state.active_formatting_elements.walk_up do |item|
          break if item.node_name == ActiveFormattingElements::MARKER

          if subject == item.node_name
            formatting_element = item
            break
          end
        end

        bail('Cannot run adoption agency when "any other end tag" is required.') if formatting_element.nil?

        unless @state.stack_of_open_elements.contains_node?(formatting_element)
          @state.active_formatting_elements.remove_node(formatting_element)
          return
        end

        return unless @state.stack_of_open_elements.has_element_in_scope?(formatting_element.node_name)

        is_above_formatting_element = true
        furthest_block = nil
        @state.stack_of_open_elements.walk_down do |item|
          if is_above_formatting_element && formatting_element.bookmark_name != item.bookmark_name
            next
          end

          if is_above_formatting_element
            is_above_formatting_element = false
            next
          end

          if self.class.special?(item)
            furthest_block = item
            break
          end
        end

        if furthest_block.nil?
          @state.stack_of_open_elements.walk_up do |item|
            @state.stack_of_open_elements.pop
            if formatting_element.bookmark_name == item.bookmark_name
              @state.active_formatting_elements.remove_node(formatting_element)
              return
            end
          end
        end

        bail("Cannot extract common ancestor in adoption agency algorithm.")
      end

      bail("Cannot run adoption agency when looping required.")
    end

    # Legacy: class-wp-html-processor.php:6215.
    def close_cell
      generate_implied_end_tags

      @state.stack_of_open_elements.walk_up do |element|
        @state.stack_of_open_elements.pop
        break if element.node_name == "TD" || element.node_name == "TH"
      end

      @state.active_formatting_elements.clear_up_to_last_marker
      @state.insertion_mode = ProcessorState::INSERTION_MODE_IN_ROW
    end

    # Legacy: class-wp-html-processor.php:6238.
    def insert_html_element(token)
      @state.stack_of_open_elements.push(token)
    end

    # Legacy: class-wp-html-processor.php:6255.
    def insert_foreign_element(token, _only_add_to_element_stack)
      adjusted_current_node = get_adjusted_current_node

      token.namespace = adjusted_current_node ? adjusted_current_node.namespace : "html"

      if mathml_integration_point?
        token.integration_node_type = "math"
      elsif html_integration_point?
        token.integration_node_type = "html"
      end

      insert_html_element(token)
    end

    # A node the tree construction algorithm implied but which is not in the source.
    # BR-MIGRATE-223. Legacy: class-wp-html-processor.php:6295.
    def insert_virtual_node(token_name, bookmark_name = nil)
      here = @bookmarks[@state.current_token.bookmark_name]
      name = bookmark_name || bookmark_token

      @bookmarks[name] = Span.new(here.start, 0)

      token = Token.new(name, token_name, false)
      insert_html_element(token)
      token
    end

    # Legacy: class-wp-html-processor.php:6320.
    def mathml_integration_point?
      current_token = @state.current_token
      return false if current_token.nil?
      return false if current_token.namespace != "math" || current_token.node_name[0] != "M"

      %w[MI MO MN MS MTEXT].include?(current_token.node_name)
    end

    # Legacy: class-wp-html-processor.php:6357.
    def html_integration_point?
      current_token = @state.current_token
      return false if current_token.nil?
      return false if current_token.namespace == "html"

      tag_name = current_token.node_name

      if current_token.namespace == "svg"
        return %w[DESC FOREIGNOBJECT TITLE].include?(tag_name)
      end

      if current_token.namespace == "math"
        return false if tag_name != "ANNOTATION-XML"

        encoding = get_attribute("encoding")
        return encoding.is_a?(String) &&
               (encoding.casecmp("application/xhtml+xml").zero? || encoding.casecmp("text/html").zero?)
      end

      bail("Should not have reached end of HTML Integration Point detection: check HTML API code.")
    end

    # BR-MIGRATE-221 / BR-MIGRATE-223 — resets tree construction so a backward seek can
    # replay it. Legacy: class-wp-html-processor.php:5546.
    def rewind_to_start
      @state.stack_of_open_elements.walk_up.to_a.each do |item|
        @state.stack_of_open_elements.remove_node(item)
      end
      @state.active_formatting_elements.walk_up.to_a.each do |item|
        @state.active_formatting_elements.remove_node(item)
      end

      @state.frameset_ok = true
      @state.stack_of_template_insertion_modes = []
      @state.head_element = nil
      @state.form_element = nil
      @state.current_token = nil
      @current_element = nil
      @element_queue = []

      if @context_node.nil?
        change_parsing_namespace("html")
        @state.insertion_mode = ProcessorState::INSERTION_MODE_INITIAL
        @breadcrumbs = []

        @bookmarks["initial"] = Span.new(0, 0)
        super_seek("initial")
        @bookmarks.delete("initial")
      else
        @state.stack_of_open_elements.push(Token.new("root-node", "HTML", false))
        change_parsing_namespace(@context_node.integration_node_type ? "html" : @context_node.namespace)

        if @context_node.node_name == "TEMPLATE"
          @state.stack_of_template_insertion_modes << ProcessorState::INSERTION_MODE_IN_TEMPLATE
        end

        reset_insertion_mode_appropriately
        @breadcrumbs = @breadcrumbs[0, 2]
        super_seek(@context_node.bookmark_name)
      end
    end

    # Calls the Tag Processor's `seek`, bypassing this class's tree-aware override.
    def super_seek(bookmark_name)
      TagProcessor.instance_method(:seek).bind(self).call(bookmark_name)
    end
  end
end
