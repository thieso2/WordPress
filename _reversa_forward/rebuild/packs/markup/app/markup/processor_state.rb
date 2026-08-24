# frozen_string_literal: true

module Markup
  # All mutable tree-construction state for one HTML Processor.
  #
  # BR-MIGRATE-223. Insertion-mode values are preserved verbatim from the legacy so that
  # a failure message naming a mode reads the same as it did in PHP.
  #
  # Legacy: wp-includes/html-api/class-wp-html-processor-state.php:23.
  class ProcessorState
    INSERTION_MODE_INITIAL = "insertion-mode-initial"
    INSERTION_MODE_BEFORE_HTML = "insertion-mode-before-html"
    INSERTION_MODE_BEFORE_HEAD = "insertion-mode-before-head"
    INSERTION_MODE_IN_HEAD = "insertion-mode-in-head"
    INSERTION_MODE_IN_HEAD_NOSCRIPT = "insertion-mode-in-head-noscript"
    INSERTION_MODE_AFTER_HEAD = "insertion-mode-after-head"
    INSERTION_MODE_IN_BODY = "insertion-mode-in-body"
    INSERTION_MODE_IN_TABLE = "insertion-mode-in-table"
    INSERTION_MODE_IN_TABLE_TEXT = "insertion-mode-in-table-text"
    INSERTION_MODE_IN_CAPTION = "insertion-mode-in-caption"
    INSERTION_MODE_IN_COLUMN_GROUP = "insertion-mode-in-column-group"
    INSERTION_MODE_IN_TABLE_BODY = "insertion-mode-in-table-body"
    INSERTION_MODE_IN_ROW = "insertion-mode-in-row"
    INSERTION_MODE_IN_CELL = "insertion-mode-in-cell"
    INSERTION_MODE_IN_SELECT = "insertion-mode-in-select"
    INSERTION_MODE_IN_SELECT_IN_TABLE = "insertion-mode-in-select-in-table"
    INSERTION_MODE_IN_TEMPLATE = "insertion-mode-in-template"
    INSERTION_MODE_AFTER_BODY = "insertion-mode-after-body"
    INSERTION_MODE_IN_FRAMESET = "insertion-mode-in-frameset"
    INSERTION_MODE_AFTER_FRAMESET = "insertion-mode-after-frameset"
    INSERTION_MODE_AFTER_AFTER_BODY = "insertion-mode-after-after-body"
    INSERTION_MODE_AFTER_AFTER_FRAMESET = "insertion-mode-after-after-frameset"

    attr_accessor :stack_of_template_insertion_modes, :stack_of_open_elements,
                  :active_formatting_elements, :current_token, :insertion_mode,
                  :context_node, :encoding, :encoding_confidence, :head_element,
                  :form_element, :frameset_ok

    def initialize
      @stack_of_template_insertion_modes = []
      @stack_of_open_elements = OpenElements.new
      @active_formatting_elements = ActiveFormattingElements.new
      @current_token = nil
      @insertion_mode = INSERTION_MODE_INITIAL
      @context_node = nil
      @encoding = nil
      @encoding_confidence = "tentative"
      @head_element = nil
      @form_element = nil
      @frameset_ok = true
    end
  end
end
