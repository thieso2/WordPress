# frozen_string_literal: true

module Markup
  # Raised when the HTML Processor recognises that it cannot proceed correctly.
  #
  # BR-MIGRATE-225 — the defining rule of this module. The HTML API targets the HTML5
  # specification but does not implement all of it. Where it lacks support it refuses to
  # guess: it aborts the parse and reports why, rather than emitting a tree that would be
  # subtly wrong. Everything carried here exists to reconstruct the failure: the token it
  # stopped on, the byte offset, the raw text of that token, and the two stacks that
  # define tree-construction state at that moment.
  #
  # Legacy: wp-includes/html-api/class-wp-html-unsupported-exception.php:30.
  class UnsupportedException < StandardError
    attr_reader :token_name, :token_at, :token, :stack_of_open_elements,
                :active_formatting_elements

    def initialize(message, token_name, token_at, token, stack_of_open_elements,
                   active_formatting_elements)
      super(message)
      @token_name = token_name
      @token_at = token_at
      @token = token
      @stack_of_open_elements = stack_of_open_elements
      @active_formatting_elements = active_formatting_elements
    end
  end
end
