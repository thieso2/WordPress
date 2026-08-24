# frozen_string_literal: true

module Sanitizing
  # Markup that has passed the allowlist, as a type.
  #
  # parity_tests/05-kses-sanitization.feature, scenario "Sanitized markup is a
  # distinct type": architecture.md §4 records the legacy's output escaping as
  # "convention only, no type system" (F-FMT-02). Nothing in PHP distinguishes a
  # string that survived wp_kses() from one that did not; the only defence was
  # remembering to call the right function. This is the one guarantee the target
  # adds, and it is the reason the scenario is marked @invariant rather than
  # @parity: it has no legacy counterpart to compare against.
  #
  # A SafeHtml can only be constructed by this pack, from a value that has just
  # been through Kses. Rendering code takes SafeHtml; handing it a bare String is
  # a TypeError, not a silent XSS.
  class SafeHtml
    attr_reader :to_s

    # BR-MIGRATE-298 (BR-KSES-01) — the only constructor: filter, then wrap.
    def self.from_post_content(raw)
      new(Kses.wp_kses_post(raw), :internal)
    end

    # BR-MIGRATE-306 (BR-KSES-09) — the same, for any named context.
    def self.from(raw, context)
      new(Kses.wp_kses(raw, context), :internal)
    end

    # Asserts that a value is already sanitized markup. Rendering code calls this
    # instead of interpolating whatever it was handed.
    def self.assert!(value)
      raise TypeError, "expected Sanitizing::SafeHtml, got #{value.class}" unless value.is_a?(SafeHtml)

      value
    end

    def initialize(html, token = nil)
      raise ArgumentError, 'use SafeHtml.from_post_content or SafeHtml.from' unless token == :internal

      @to_s = html.freeze
      freeze
    end

    def ==(other)
      other.is_a?(SafeHtml) && other.to_s == to_s
    end
    alias eql? ==

    def hash
      [SafeHtml, to_s].hash
    end

    def empty?
      to_s.empty?
    end

    def inspect
      "#<Sanitizing::SafeHtml #{to_s.inspect}>"
    end
  end
end
