# frozen_string_literal: true

module Sanitizing
  # The `style` attribute allowlist.
  #
  # Legacy: safecss_filter_attr(), wp-includes/kses.php:2647. Reached from
  # wp_kses_attr_check() (kses.php:1641) for every `style` attribute, and `style`
  # is a global attribute on every tag in $allowedposttags, so this runs on
  # essentially all post content.
  #
  # BR-MIGRATE-298 (BR-KSES-01): the same allowlist-by-regex discipline, kept
  # verbatim per owner override 2.
  module Css
    # wp-includes/kses.php:2831 — CSS properties whose value may be a url().
    URL_DATA_TYPES = %w[
      background background-image cursor filter list-style list-style-image
      clip-path fill marker marker-end marker-mid marker-start mask stroke
    ].freeze

    # wp-includes/kses.php:2924 — CSS properties that accept gradients.
    GRADIENT_DATA_TYPES = %w[background background-image].freeze

    # wp-includes/kses.php:2973 — "Simplified: matches the sequence `url(*)`."
    URL_CALL = /url\([^)]+\)/n

    # wp-includes/kses.php:2977. PCRE `\g1` is a backreference to group 1; Ruby
    # spells that `\k<1>` inside a pattern, and `.*` is greedy in both engines.
    URL_PIECES = Bytes.regexp("\\Aurl\\(\\s*(['\\\"]?)(.*)(\\k<1>)\\s*\\)#{Bytes::PCRE_EOS}")

    # wp-includes/kses.php:2999.
    GRADIENT_CALL = /(?:repeating-)?(?:linear|radial|conic)-gradient\((?:[^()]|\([^()]*\))*\)/n

    # wp-includes/kses.php:3013 — CSS functions are stripped from the *test*
    # string so their contents do not trip the unsafe-character check.
    #
    # ⚠️ PCRE→Onigmo, the single most delicate translation in this pack: PCRE's
    # recursive subpattern reference `(?1)` is spelled `\g<1>` in Onigmo. Both
    # recurse into group 1, but Onigmo has no PCRE backtrack/recursion limit, so
    # where PHP would return null on a pathological input (and the legacy then
    # `continue`s, dropping the declaration) Ruby keeps matching. See README.
    CSS_FUNCTIONS = Bytes.regexp(
      '\b(?:' \
      'var|calc|min|max|minmax|clamp|repeat' \
      '|matrix|matrix3d|perspective' \
      '|rotate|rotate3d|rotateX|rotateY|rotateZ' \
      '|scale|scale3d|scaleX|scaleY|scaleZ' \
      '|skew|skewX|skewY' \
      '|translate|translate3d|translateX|translateY|translateZ' \
      '|circle|ellipse|inset|path|polygon|rect|shape|xywh' \
      ')(\((?:[^()]|\g<1>)*\))'
    )

    # wp-includes/kses.php:3035 — "Disallow CSS containing \ ( & } = or comments".
    UNSAFE_CSS = /[\\(&=}]|\/\*/n

    # wp-includes/kses.php:2919 — CSS custom property names.
    CUSTOM_PROPERTY = Bytes.regexp("\\A--[a-zA-Z0-9\\-_]+#{Bytes::PCRE_EOS}")

    module_function

    # BR-MIGRATE-298 (BR-KSES-01) — filters a `style` attribute value down to the
    # allowed declarations. Legacy: safecss_filter_attr(), wp-includes/kses.php:2647.
    def safecss_filter_attr(css)
      css = Kses.wp_kses_no_null(css)
      css = css.gsub("\n".b, ''.b).gsub("\r".b, ''.b).gsub("\t".b, ''.b)

      allowed_protocols = Tables::ALLOWED_PROTOCOLS

      # "@todo Parse enough CSS to split rules without breaking on things like
      #  quoted strings." — the legacy's own comment, preserved behaviour.
      css_array = php_explode(';', Kses.php_trim(css))

      allowed_attr = Tables::SAFE_STYLE_CSS

      out = +''.b
      css_array.each do |css_item|
        next if css_item.empty?

        css_item = Kses.php_trim(css_item)
        css_test_string = css_item
        found = false
        url_attr = false
        gradient_attr = false
        is_custom_var = false
        parts = nil

        if !css_item.include?(':'.b)
          found = true
        else
          parts = php_explode(':', css_item, 2)
          css_selector = Kses.php_trim(parts[0])

          item_allowed = allowed_attr
          if allowed_attr.include?('--*') && CUSTOM_PROPERTY.match?(css_selector)
            item_allowed = allowed_attr + [css_selector.dup.force_encoding(Encoding::UTF_8)]
            is_custom_var = true
          end

          if item_allowed.include?(css_selector.dup.force_encoding(Encoding::UTF_8))
            found = true
            url_attr = URL_DATA_TYPES.include?(css_selector)
            gradient_attr = GRADIENT_DATA_TYPES.include?(css_selector)
          end

          if is_custom_var
            css_value = Kses.php_trim(parts[1].to_s)
            url_attr = css_value.start_with?('url('.b)
            gradient_attr = css_value.include?('-gradient('.b)
          end
        end

        if found && url_attr
          parts[1].to_s.scan(URL_CALL) do |_|
            url_match = Regexp.last_match(0)
            url_pieces = URL_PIECES.match(url_match)

            if url_pieces.nil? || url_pieces[2].nil? || url_pieces[2].empty? || url_pieces[2] == '0'.b
              found = false
              break
            end

            url = Kses.php_trim(url_pieces[2])

            if url.empty? || url == '0'.b || Kses.wp_kses_bad_protocol(url, allowed_protocols) != url
              found = false
              break
            end

            css_test_string = css_test_string.gsub(url_match, ''.b)
          end
        end

        if found && gradient_attr
          css_test_string.scan(GRADIENT_CALL) do |_|
            css_test_string = css_test_string.gsub(Regexp.last_match(0), ''.b)
          end
        end

        next unless found

        css_test_string = css_test_string.gsub(CSS_FUNCTIONS, ''.b)

        next unless UNSAFE_CSS.match?(css_test_string) == false

        out << ';'.b unless out.empty?
        out << css_item
      end

      out
    end

    # PHP explode() keeps empty fields and, with a limit, puts the whole
    # remainder in the last field. Ruby's String#split does the same only when a
    # limit is given, so the no-limit case needs -1.
    def php_explode(sep, str, limit = -1)
      Bytes.binary(str).split(Bytes.binary(sep), limit)
    end
  end
end
