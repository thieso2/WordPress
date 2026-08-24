# frozen_string_literal: true

module Styling
  # The CSS-selector algebra WP_Theme_JSON runs on: splitting a selector list,
  # appending a pseudo-class to every branch of it, prepending an ancestor, and
  # scoping one list by another.
  #
  # These are `protected static` methods on the god-object
  # (class-wp-theme-json.php:1488, :1537, :1612, :2687). They are pure string
  # functions with no state, so they are lifted into their own module rather than
  # carried along as another 200 lines of WP_Theme_JSON.
  #
  # ⚠️ PCRE→Onigmo: `strcspn` has no Ruby equivalent, so the scan loop below uses
  # `String#index` with a character class. The semantics that matter are (a) the
  # BYTE-for-byte identical split points and (b) trimming with the CSS whitespace
  # set `" \t\n"` only — `\r` and `\f` are NOT trimmed, because CSS preprocessing
  # has already converted them (class-wp-theme-json.php:1706).
  module Selectors
    CSS_WHITESPACE = " \t\n"
    # The characters that can begin a construct in which a comma is not a
    # delimiter: comment, comma, string, parentheses, CDO/CDC, escape.
    DELIMITERS = /[\/,'"()<\-\\]/
    # The fast-path guard, class-wp-theme-json.php:1512: if none of these appear,
    # every comma is a comma token.
    NO_SPECIALS = /[\/'"(<\\]/

    class << self
      # class-wp-theme-json.php:1612 — parses a selector list into its branches.
      #
      # @param selector [String]
      # @return [Array<String>]
      def split_selector_list(selector)
        selector = selector.to_s
        return [trim_css(selector)] unless selector.include?(',')

        selectors = []
        length = selector.length
        parentheses_depth = 0
        at = 0
        was_at = 0

        while at < length
          next_at = selector.index(DELIMITERS, at)
          break if next_at.nil? || next_at >= length

          next_cp = selector[next_at]

          # Escaped syntax characters do not act as delimiters.
          if next_cp == '\\'
            at = [next_at + 2, length].min
            next
          end

          # No selector list is ever split inside parentheses.
          if next_cp == '(' || next_cp == ')'
            parentheses_depth += (next_cp == '(' ? 1 : -1)
            at = next_at + 1
            next
          end

          # A string is incorporated into the selector it is found in.
          if next_cp == "'" || next_cp == '"'
            at = end_of_string(selector, next_at, next_cp)
            next
          end

          # A comment is incorporated into the selector it is found in.
          if next_cp == '/' && (next_at + 1) < length && selector[next_at + 1] == '*'
            comment_end = selector.index('*/', next_at + 1)
            at = comment_end.nil? ? length : comment_end + 2
            next
          end

          # A CDO (`<!--`) or CDC (`-->`) is likewise incorporated.
          if (next_cp == '<' && selector[next_at, 4] == '<!--') ||
             (next_cp == '-' && selector[next_at, 3] == '-->')
            at = next_at + (next_cp == '<' ? 4 : 3)
            next
          end

          if next_cp == ',' && parentheses_depth.zero?
            selectors << trim_css(selector[was_at, next_at - was_at])
            at = next_at + 1
            was_at = at
            next
          end

          at = next_at + 1
        end

        selectors << trim_css(selector[was_at..].to_s) if was_at < length
        selectors
      end

      # class-wp-theme-json.php:1488 — `h1, h2` + `:hover` => `h1:hover, h2:hover`.
      #
      # @param selector [String]
      # @param to_append [String]
      # @return [String]
      def append_to_selector(selector, to_append)
        selector = selector.to_s
        return trim_css(selector) + to_append unless selector.include?(',')

        # :1512 — the fast path, taken when no comma can mean anything else.
        unless selector.match?(NO_SPECIALS)
          return trim_css(selector).gsub(/[ \t\n]*,[ \t\n]*/, "#{to_append}, ") + to_append
        end

        split_selector_list(selector).map { |sel| sel + to_append }.join(', ')
      end

      # class-wp-theme-json.php:1537 — `h1, h2` prefixed with `.x ` =>
      # `.x h1, .x h2`.
      #
      # @param selector [String]
      # @param to_prepend [String]
      # @return [String]
      def prepend_to_selector(selector, to_prepend)
        selector = selector.to_s
        return to_prepend + trim_css(selector) unless selector.include?(',')

        unless selector.match?(NO_SPECIALS)
          return to_prepend + trim_css(selector).gsub(/[ \t\n]*,[ \t\n]*/, ", #{to_prepend}")
        end

        split_selector_list(selector).map { |sel| to_prepend + sel }.join(', ')
      end

      # class-wp-theme-json.php:2687 — the cross product of two selector lists.
      #
      # @param scope [String]
      # @param selector [String]
      # @return [String]
      def scope_selector(scope, selector)
        return selector if PhpCompat.php_empty?(scope) || PhpCompat.php_empty?(selector)

        scoped = []
        split_selector_list(scope).each do |outer|
          split_selector_list(selector).each do |inner|
            if !PhpCompat.php_empty?(outer) && !PhpCompat.php_empty?(inner)
              scoped << "#{outer} #{inner}"
            elsif PhpCompat.php_empty?(outer)
              scoped << inner
            elsif PhpCompat.php_empty?(inner)
              scoped << outer
            end
          end
        end
        scoped.join(', ')
      end

      # class-wp-theme-json.php:5866 — appends `.is-style-<name>` to the ANCESTOR
      # of each branch: the first run of characters before a combinator or a
      # pseudo-class, first match only.
      #
      # @param variation_name [String]
      # @param block_selector [String, nil]
      # @return [String]
      def block_style_variation_selector(variation_name, block_selector)
        variation_class = ".is-style-#{variation_name}"
        return variation_class if PhpCompat.php_empty?(block_selector)

        split_selector_list(block_selector).map { |part|
          replaced = false
          part.gsub(/[^\s:]+/) do |match|
            next match if replaced

            replaced = true
            "#{match}#{variation_class}"
          end
        }.join(', ')
      end

      # class-wp-theme-json.php:5918.
      #
      # @param style_variation [Hash]
      # @param feature_selector [String]
      # @return [String]
      def block_style_variation_feature_selector(style_variation, feature_selector)
        variation_path = style_variation['path'] || []
        variation_name = style_variation['name'] ||
                         (variation_path.is_a?(Array) ? variation_path.last : nil)
        return style_variation['selector'] || feature_selector if PhpCompat.php_empty?(variation_name)

        prefix = ".is-style-#{variation_name} "
        parts = split_selector_list(feature_selector).map do |sel|
          sel.start_with?(prefix) ? sel[prefix.length..] : sel
        end
        block_style_variation_selector(variation_name, parts.join(', '))
      end

      # `trim($s, " \t\n")` — NOT Ruby's `strip`, which also removes `\r`, `\f`
      # and `\0`. class-wp-theme-json.php:1697 explains why the set is exactly
      # these three.
      #
      # @param str [String]
      # @return [String]
      def trim_css(str) = str.to_s.gsub(/\A[ \t\n]+/, '').gsub(/[ \t\n]+\z/, '')

      private

      # PHP's inner `strcspn` loop for a quoted string, :1652.
      def end_of_string(selector, opened_at, quote)
        length = selector.length
        at = opened_at + 1
        while at < length
          at = selector.index(/[#{Regexp.escape(quote)}\\]/, at) || length
          break if at >= length

          if selector[at] == '\\'
            at += 2
            next
          end
          if selector[at] == quote
            at += 1
            break
          end
          at += 1
        end
        at
      end
    end
  end
end
