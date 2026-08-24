# frozen_string_literal: true

module Markup
  # A push or pop of the stack of open elements, queued for the caller to visit.
  #
  # BR-MIGRATE-223: because there is no tree, the only way to expose "an element opened"
  # and "an element closed" to a caller is to record every stack operation and replay it
  # as a token. `provenance` distinguishes operations that correspond to real text in the
  # document from ones the tree construction algorithm implied.
  #
  # Legacy: wp-includes/html-api/class-wp-html-stack-event.php:22.
  class StackEvent
    POP = "pop"
    PUSH = "push"

    attr_accessor :token, :operation, :provenance

    def initialize(token, operation, provenance)
      @token = token
      @operation = operation
      @provenance = provenance
    end
  end
end
