# frozen_string_literal: true

module Markup
  # The HTML5 stack of open elements.
  #
  # BR-MIGRATE-223 — this is one of the two structures that make tree construction
  # possible without a tree. It is the ancestor chain of the node currently being
  # processed, and it is what `get_breadcrumbs` (BR-MIGRATE-226) is derived from.
  #
  # The push and pop handlers are how the HTML Processor learns that an element opened or
  # closed, including elements that were never written in the source; see
  # Markup::StackEvent.
  #
  # Legacy: wp-includes/html-api/class-wp-html-open-elements.php:31.
  class OpenElements
    # Elements that terminate a search for "an element in scope".
    # Legacy: class-wp-html-open-elements.php:304.
    SCOPE_TERMINATORS = %w[
      APPLET CAPTION HTML TABLE TD TH MARQUEE OBJECT SELECT TEMPLATE
    ].freeze

    FOREIGN_SCOPE_TERMINATORS = [
      "math MI", "math MO", "math MN", "math MS", "math MTEXT", "math ANNOTATION-XML",
      "svg FOREIGNOBJECT", "svg DESC", "svg TITLE"
    ].freeze

    LIST_ITEM_SCOPE_TERMINATORS =
      (SCOPE_TERMINATORS + %w[BUTTON OL UL] + FOREIGN_SCOPE_TERMINATORS).freeze
    BUTTON_SCOPE_TERMINATORS =
      (SCOPE_TERMINATORS + %w[BUTTON] + FOREIGN_SCOPE_TERMINATORS).freeze
    IN_SCOPE_TERMINATORS = (SCOPE_TERMINATORS + FOREIGN_SCOPE_TERMINATORS).freeze
    TABLE_SCOPE_TERMINATORS = %w[HTML TABLE TEMPLATE].freeze

    # The spec has no "H1 through H6" element, so the HTML API uses this sentinel to ask
    # about the whole family at once. Preserved verbatim from the legacy.
    H1_THROUGH_H6 = "(internal: H1 through H6 - do not use)"
    HEADINGS = %w[H1 H2 H3 H4 H5 H6].freeze

    attr_reader :stack

    def initialize
      @stack = []
      @has_p_in_button_scope = false
      @pop_handler = nil
      @push_handler = nil
    end

    def set_pop_handler(handler)
      @pop_handler = handler
    end

    def set_push_handler(handler)
      @push_handler = handler
    end

    # Legacy: class-wp-html-open-elements.php:120.
    def at(nth)
      @stack[nth - 1]
    end

    # Legacy: class-wp-html-open-elements.php:138.
    def contains?(node_name)
      @stack.any? { |item| item.namespace == "html" && item.node_name == node_name }
    end

    # Legacy: class-wp-html-open-elements.php:156.
    def contains_node?(token)
      @stack.any? { |item| item.equal?(token) }
    end

    def count
      @stack.length
    end

    # Legacy: class-wp-html-open-elements.php:185.
    def current_node
      @stack.last
    end

    # Legacy: class-wp-html-open-elements.php:218.
    def current_node_is?(identity)
      current = @stack.last
      return false if current.nil?

      name = current.node_name
      name == identity ||
        (identity == "#doctype" && name == "html") ||
        (identity == "#tag" && name.match?(/\A[A-Z]+\z/))
    end

    # Legacy: class-wp-html-open-elements.php:244.
    def has_element_in_specific_scope?(tag_name, termination_list)
      walk_up do |node|
        namespaced_name = node.namespace == "html" ? node.node_name : "#{node.namespace} #{node.node_name}"

        return true if namespaced_name == tag_name
        return true if tag_name == H1_THROUGH_H6 && HEADINGS.include?(namespaced_name)
        return false if termination_list.include?(namespaced_name)
      end

      false
    end

    def has_element_in_scope?(tag_name)
      has_element_in_specific_scope?(tag_name, IN_SCOPE_TERMINATORS)
    end

    def has_element_in_list_item_scope?(tag_name)
      has_element_in_specific_scope?(tag_name, LIST_ITEM_SCOPE_TERMINATORS)
    end

    def has_element_in_button_scope?(tag_name)
      has_element_in_specific_scope?(tag_name, BUTTON_SCOPE_TERMINATORS)
    end

    def has_element_in_table_scope?(tag_name)
      has_element_in_specific_scope?(tag_name, TABLE_SCOPE_TERMINATORS)
    end

    # Cached because `in body` insertion consults it on nearly every start tag.
    # Legacy: class-wp-html-open-elements.php:498.
    def has_p_in_button_scope?
      @has_p_in_button_scope
    end

    # Legacy: class-wp-html-open-elements.php:511.
    def pop
      item = @stack.pop
      return false if item.nil?

      after_element_pop(item)
      true
    end

    # Legacy: class-wp-html-open-elements.php:531.
    def pop_until(html_tag_name)
      until @stack.empty?
        item = @stack.last
        pop

        next unless item.namespace == "html"

        return true if html_tag_name == H1_THROUGH_H6 && HEADINGS.include?(item.node_name)
        return true if html_tag_name == item.node_name
      end

      false
    end

    # Legacy: class-wp-html-open-elements.php:563.
    def push(stack_item)
      @stack << stack_item
      after_element_push(stack_item)
    end

    # Legacy: class-wp-html-open-elements.php:576.
    def remove_node(token)
      index = @stack.rindex { |item| token.bookmark_name == item.bookmark_name }
      return false if index.nil?

      item = @stack.delete_at(index)
      after_element_pop(item)
      true
    end

    # Iterates the stack from the root toward the current node.
    def walk_down(&block)
      return to_enum(:walk_down) unless block

      @stack.each(&block)
    end

    # Iterates from the current node up toward the root, optionally starting just above a
    # given node.
    # Legacy: class-wp-html-open-elements.php:642.
    def walk_up(above_this_node = nil)
      return to_enum(:walk_up, above_this_node) unless block_given?

      has_found_node = above_this_node.nil?

      (@stack.length - 1).downto(0) do |i|
        node = @stack[i]

        unless has_found_node
          has_found_node = node.equal?(above_this_node)
          next
        end

        yield node
      end
    end

    # Legacy: class-wp-html-open-elements.php:674.
    def after_element_push(item)
      namespaced_name = item.namespace == "html" ? item.node_name : "#{item.namespace} #{item.node_name}"

      if BUTTON_SCOPE_TERMINATORS.include?(namespaced_name)
        @has_p_in_button_scope = false
      elsif namespaced_name == "P"
        @has_p_in_button_scope = true
      end

      @push_handler&.call(item)
    end

    # Legacy: class-wp-html-open-elements.php:730.
    def after_element_pop(item)
      namespaced_name = item.namespace == "html" ? item.node_name : "#{item.namespace} #{item.node_name}"

      if namespaced_name == "P" || BUTTON_SCOPE_TERMINATORS.include?(namespaced_name)
        @has_p_in_button_scope = has_element_in_button_scope?("P")
      end

      @pop_handler&.call(item)
    end

    # Legacy: class-wp-html-open-elements.php:781.
    def clear_to_table_context
      clear_until(%w[TABLE TEMPLATE HTML])
    end

    # Legacy: class-wp-html-open-elements.php:805.
    def clear_to_table_body_context
      clear_until(%w[TBODY TFOOT THEAD TEMPLATE HTML])
    end

    # Legacy: class-wp-html-open-elements.php:831.
    def clear_to_table_row_context
      clear_until(%w[TR TEMPLATE HTML])
    end

    private

    def clear_until(stop_names)
      until @stack.empty?
        break if stop_names.include?(@stack.last.node_name)

        pop
      end
    end
  end
end
