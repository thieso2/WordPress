# frozen_string_literal: true

module Styling
  # `wp_get_typography_font_size_value()`, wp-includes/block-supports/typography.php:565,
  # with `wp_get_typography_value_and_unit()` (:368) and
  # `wp_get_computed_fluid_typography_value()` (:464).
  #
  # BR-MIGRATE-212: a `fontSizes` preset becomes a CSS custom property. WHAT it
  # becomes is decided here — `settings.typography.fluid` turns `1rem` into
  # `clamp(1rem, 1rem + ((1vw - 0.2rem) * 0.196), 1.125rem)`, and twentytwentyfive
  # switches it on, so the non-fluid shortcut the pack shipped in Wave 0 was wrong
  # for every font-size variable on every screen.
  #
  # ⚠️ AD-01: `wp_get_global_settings()` (:591) is a cache-backed global read. Here
  # the caller passes the settings in, and `wp_parse_args` against the document's
  # own root settings replaces the global fallback — the same values, without the
  # global.
  module FluidTypography
    ACCEPTABLE_UNITS = %w[rem px em].freeze
    DEFAULT_MAXIMUM_VIEWPORT_WIDTH = '1600px'
    DEFAULT_MINIMUM_VIEWPORT_WIDTH = '320px'
    DEFAULT_MINIMUM_FONT_SIZE_FACTOR_MAX = 0.75
    DEFAULT_MINIMUM_FONT_SIZE_FACTOR_MIN = 0.25
    DEFAULT_SCALE_FACTOR = 1
    DEFAULT_MINIMUM_FONT_SIZE_LIMIT = '14px'

    class << self
      # typography.php:565.
      #
      # @param preset [Hash] a `fontSizes` preset, or `{'size' => value}`
      # @param settings [Hash] the theme.json settings that apply
      # @return [String, nil]
      def font_size_value(preset, settings = {})
        return nil unless preset.is_a?(Hash) && preset.key?('size')

        size = preset['size']
        fluid_settings_for_preset = preset['fluid']
        # :575 — `false` disables fluidity for this preset; `0`/`''` cannot be
        # made fluid at all.
        return size if fluid_settings_for_preset == false || PhpCompat.php_empty?(size)

        settings = {} unless settings.is_a?(Hash)
        typography_settings = settings['typography'].is_a?(Hash) ? settings['typography'] : {}

        # :606 — fluid is off AND the preset does not switch it on for itself.
        if PhpCompat.php_empty?(typography_settings['fluid']) &&
           PhpCompat.php_empty?(fluid_settings_for_preset)
          return size
        end

        # `settings.typography.fluid` is `true` for twentytwentyfive, and PHP's
        # `true['minViewportWidth']` is null rather than an error, so every lookup
        # below falls through to its default.
        fluid_settings = typography_settings['fluid'].is_a?(Hash) ? typography_settings['fluid'] : {}
        layout_settings = settings['layout'].is_a?(Hash) ? settings['layout'] : {}

        minimum_viewport_width = fluid_settings['minViewportWidth'] || DEFAULT_MINIMUM_VIEWPORT_WIDTH
        maximum_viewport_width =
          if layout_settings.key?('wideSize') && !PhpCompat.php_empty?(value_and_unit(layout_settings['wideSize']))
            layout_settings['wideSize']
          else
            DEFAULT_MAXIMUM_VIEWPORT_WIDTH
          end
        maximum_viewport_width = fluid_settings['maxViewportWidth'] if fluid_settings.key?('maxViewportWidth')

        has_min_font_size = fluid_settings.key?('minFontSize') &&
                            !PhpCompat.php_empty?(value_and_unit(fluid_settings['minFontSize']))
        minimum_font_size_limit = has_min_font_size ? fluid_settings['minFontSize'] : DEFAULT_MINIMUM_FONT_SIZE_LIMIT

        preset_fluid = fluid_settings_for_preset.is_a?(Hash) ? fluid_settings_for_preset : {}
        minimum_font_size_raw = preset_fluid['min']
        maximum_font_size_raw = preset_fluid['max']

        preferred_size = value_and_unit(size)
        return size if preferred_size.nil? || PhpCompat.php_empty?(preferred_size['unit'])

        minimum_font_size_limit = value_and_unit(minimum_font_size_limit, coerce_to: preferred_size['unit'])

        # :655 — the limit is not enforced when the preset states both bounds.
        if !PhpCompat.php_empty?(minimum_font_size_limit) &&
           PhpCompat.php_empty?(minimum_font_size_raw) && PhpCompat.php_empty?(maximum_font_size_raw) &&
           preferred_size['value'] <= minimum_font_size_limit['value']
          return size
        end

        if PhpCompat.php_empty?(maximum_font_size_raw)
          maximum_font_size_raw = "#{num(preferred_size['value'])}#{preferred_size['unit']}"
        end

        if PhpCompat.php_empty?(minimum_font_size_raw)
          preferred_in_px = preferred_size['unit'] == 'px' ? preferred_size['value'] : preferred_size['value'] * 16
          factor = clamp(1 - (0.075 * Math.log2(preferred_in_px)),
                         DEFAULT_MINIMUM_FONT_SIZE_FACTOR_MIN, DEFAULT_MINIMUM_FONT_SIZE_FACTOR_MAX)
          calculated = ThemeJson.php_round(preferred_size['value'] * factor, 3)
          minimum_font_size_raw =
            if !PhpCompat.php_empty?(minimum_font_size_limit) && calculated <= minimum_font_size_limit['value']
              "#{num(minimum_font_size_limit['value'])}#{minimum_font_size_limit['unit']}"
            else
              "#{num(calculated)}#{preferred_size['unit']}"
            end
        end

        computed = computed_value(minimum_viewport_width, maximum_viewport_width,
                                  minimum_font_size_raw, maximum_font_size_raw, DEFAULT_SCALE_FACTOR)
        PhpCompat.php_empty?(computed) ? size : computed
      end

      # typography.php:464.
      #
      # @return [String, nil]
      def computed_value(min_viewport_raw, max_viewport_raw, min_font_raw, max_font_raw, scale_factor)
        minimum_font_size = value_and_unit(min_font_raw)
        font_size_unit = (minimum_font_size && minimum_font_size['unit']) || 'rem'
        maximum_font_size = value_and_unit(max_font_raw, coerce_to: font_size_unit)
        return nil if maximum_font_size.nil? || minimum_font_size.nil?

        minimum_font_size_rem = value_and_unit(min_font_raw, coerce_to: 'rem')
        maximum_viewport_width = value_and_unit(max_viewport_raw, coerce_to: font_size_unit)
        minimum_viewport_width = value_and_unit(min_viewport_raw, coerce_to: font_size_unit)
        return nil if minimum_viewport_width.nil? || maximum_viewport_width.nil?

        denominator = maximum_viewport_width['value'] - minimum_viewport_width['value']
        return nil if PhpCompat.php_empty?(denominator)

        offset = "#{num(ThemeJson.php_round(minimum_viewport_width['value'] / 100, 3))}#{font_size_unit}"
        linear_factor = 100 * ((maximum_font_size['value'] - minimum_font_size['value']) / denominator)
        linear_factor_scaled = ThemeJson.php_round(linear_factor * scale_factor, 3)
        linear_factor_scaled = 1 if PhpCompat.php_empty?(linear_factor_scaled)
        # `implode('', $minimum_font_size_rem)` — value then unit, in insertion order.
        target = "#{num(minimum_font_size_rem['value'])}#{minimum_font_size_rem['unit']} + " \
                 "((1vw - #{offset}) * #{num(linear_factor_scaled)})"

        "clamp(#{min_font_raw}, #{target}, #{max_font_raw})"
      end

      # typography.php:368.
      #
      # @return [Hash{String=>Object}, nil] `{'value' =>, 'unit' =>}`
      def value_and_unit(raw_value, coerce_to: '', root_size_value: 16)
        return nil unless raw_value.is_a?(String) || raw_value.is_a?(Numeric)
        return nil if PhpCompat.php_empty?(raw_value)

        raw_value = "#{num(raw_value)}px" if raw_value.is_a?(Numeric)
        # ⚠️ `^…$` in PCRE without /D also matches before a trailing newline;
        # anchored with \A…\z here so `"1rem\n"` cannot slip through into a
        # `clamp()`.
        match = raw_value.to_s.match(/\A(\d*\.?\d+)([a-zA-Z]+|%)\z/)
        return nil if match.nil?

        value = match[1].to_f
        unit = match[2]
        return nil unless ACCEPTABLE_UNITS.include?(unit)

        if coerce_to == 'px' && %w[em rem].include?(unit)
          value *= root_size_value
          unit = coerce_to
        end
        if unit == 'px' && %w[em rem].include?(coerce_to)
          value /= root_size_value
          unit = coerce_to
        end
        unit = coerce_to if %w[em rem].include?(coerce_to) && %w[em rem].include?(unit)

        { 'value' => ThemeJson.php_round(value, 3), 'unit' => unit }
      end

      # PHP's `clamp()` polyfill, wp-includes/compat.php:715.
      def clamp(value, min, max) = [[value, min].max, max].min

      # PHP renders `(string) 9.6` as "9.6" and `(string) 1.0` as "1".
      def num(value) = PhpCompat.to_php_string(value)
    end
  end
end
