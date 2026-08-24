# frozen_string_literal: true

module Markup
  # The HTML5 list of active formatting elements.
  #
  # BR-MIGRATE-223 — the second structure tree construction needs. It remembers the
  # formatting elements (`B`, `I`, `A`, …) that are still in effect so that misnested
  # markup such as `<b><p>one</b>two` can be reconstructed the way a browser would, and it
  # is what the adoption agency algorithm operates on.
  #
  # Legacy: wp-includes/html-api/class-wp-html-active-formatting-elements.php:37.
  class ActiveFormattingElements
    MARKER = "marker"

    def initialize
      @stack = []
    end

    # Legacy: class-wp-html-active-formatting-elements.php:55.
    def contains_node?(token)
      @stack.any? { |item| token.bookmark_name == item.bookmark_name }
    end

    def count
      @stack.length
    end

    def current_node
      @stack.last
    end

    # Markers fence off a region of the list; `APPLET`, `MARQUEE`, `OBJECT`, table cells
    # and captions all insert one so that formatting cannot leak across them.
    # Legacy: class-wp-html-active-formatting-elements.php:102.
    def insert_marker
      push(Token.new(nil, MARKER, false))
    end

    # Legacy: class-wp-html-active-formatting-elements.php:114.
    #
    # NOT PORTED (as in the legacy): the "Noah's Ark clause", which caps the list at three
    # identical formatting elements. The legacy carries an explicit @todo saying the same;
    # porting it would be a behaviour change, not a port.
    def push(token)
      @stack << token
    end

    # Legacy: class-wp-html-active-formatting-elements.php:139.
    def remove_node(token)
      index = @stack.rindex { |item| token.bookmark_name == item.bookmark_name }
      return false if index.nil?

      @stack.delete_at(index)
      true
    end

    def walk_down(&block)
      return to_enum(:walk_down) unless block

      @stack.each(&block)
    end

    def walk_up(&block)
      return to_enum(:walk_up) unless block

      @stack.reverse_each(&block)
    end

    # Legacy: class-wp-html-active-formatting-elements.php:222.
    def clear_up_to_last_marker
      until @stack.empty?
        item = @stack.pop
        break if item.node_name == MARKER
      end
    end
  end
end
