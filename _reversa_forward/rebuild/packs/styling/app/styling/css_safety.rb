# frozen_string_literal: true

module Styling
  # Port of the CSS-safety half of wp-includes/kses.php, restricted to what the
  # style engine actually calls: `safecss_filter_attr()` and the protocol
  # checking it performs on `url()` values.
  #
  # Lives inside this pack rather than being borrowed from `sanitizing` because
  # topology_decision.md option 3 gives every pack zero dependencies.
  #
  # paradigm_decision.md option 1: the `safe_style_css`,
  # `safecss_filter_attr_allow_css` and `kses_allowed_protocols` filters are not
  # implemented. The lists below are WordPress's unfiltered defaults and are the
  # permanent, only behaviour.
  module CssSafety
    module_function

    # `safe_style_css` default — wp-includes/kses.php:2668.
    ALLOWED_ATTR = %w[
      background background-color background-image background-position
      background-repeat background-size background-attachment background-blend-mode
      border border-radius border-width border-color border-style
      border-right border-right-color border-right-style border-right-width
      border-bottom border-bottom-color border-bottom-left-radius
      border-bottom-right-radius border-bottom-style border-bottom-width
      border-bottom-right-radius border-bottom-left-radius
      border-left border-left-color border-left-style border-left-width
      border-top border-top-color border-top-left-radius border-top-right-radius
      border-top-style border-top-width border-top-left-radius border-top-right-radius
      border-spacing border-collapse caption-side
      columns column-count column-fill column-gap column-rule column-span column-width
      display
      color filter font font-family font-size font-style font-variant font-weight
      letter-spacing line-height text-align text-decoration text-indent
      text-transform white-space
      height min-height max-height
      width min-width max-width
      margin margin-right margin-bottom margin-left margin-top
      margin-block-start margin-block-end margin-inline-start margin-inline-end
      padding padding-right padding-bottom padding-left padding-top
      padding-block-start padding-block-end padding-inline-start padding-inline-end
      flex flex-basis flex-direction flex-flow flex-grow flex-shrink flex-wrap
      gap column-gap row-gap
      grid-template-columns grid-auto-columns grid-column-start grid-column-end
      grid-column grid-column-gap grid-template-rows grid-auto-rows grid-row-start
      grid-row-end grid-row grid-row-gap grid-gap
      justify-content justify-items justify-self
      align-content align-items align-self
      clear cursor direction float list-style-type object-fit object-position
      opacity overflow vertical-align writing-mode
      position top right bottom left z-index box-shadow aspect-ratio container-type
      fill fill-opacity fill-rule
      stroke stroke-dasharray stroke-dashoffset stroke-linecap stroke-linejoin
      stroke-miterlimit stroke-opacity stroke-width
      color-interpolation color-interpolation-filters paint-order stop-color
      stop-opacity flood-color flood-opacity lighting-color
      marker marker-end marker-mid marker-start
      clip-path clip-rule mask mask-type
      cx cy r rx ry x y d
      alignment-baseline baseline-shift dominant-baseline
      glyph-orientation-horizontal glyph-orientation-vertical text-anchor
      unicode-bidi word-spacing
      font-size-adjust font-stretch
      color-rendering image-rendering shape-rendering text-rendering vector-effect
      transform transform-origin
      pointer-events visibility
      --*
    ].freeze

    # wp-includes/kses.php:2901.
    URL_DATA_TYPES = %w[
      background background-image cursor filter list-style list-style-image
      clip-path fill marker marker-end marker-mid marker-start mask stroke
    ].freeze

    # wp-includes/kses.php:2926.
    GRADIENT_DATA_TYPES = %w[background background-image].freeze

    # `wp_allowed_protocols()` default — wp-includes/functions.php.
    ALLOWED_PROTOCOLS = %w[
      http https ftp ftps mailto news irc irc6 ircs gopher nntp feed telnet mms
      rtsp sms svn tel fax xmpp webcal urn
    ].freeze

    CUSTOM_PROPERTY_NAME = /\A--[a-zA-Z0-9\-_]+\z/
    URL_CALL = /url\([^)]+\)/
    # PCRE `\g1` (backreference) becomes Ruby `\1`; PCRE `$` becomes `\z`
    # because Ruby's `$` is a line anchor. Newlines are stripped upstream, so
    # the two are equivalent here.
    URL_PIECES = /\Aurl\(\s*(['"]?)(.*)(\1)\s*\)\z/
    GRADIENT_CALL = /(?:repeating-)?(?:linear|radial|conic)-gradient\((?:[^()]|\([^()]*\))*\)/
    # PCRE recursion `(?1)` becomes Onigmo subexpression call `\g<1>`.
    CSS_FUNCTION_CALL = /
      \b(?:
        var|calc|min|max|minmax|clamp|repeat
        |matrix|matrix3d|perspective
        |rotate|rotate3d|rotateX|rotateY|rotateZ
        |scale|scale3d|scaleX|scaleY|scaleZ
        |skew|skewX|skewY
        |translate|translate3d|translateX|translateY|translateZ
        |circle|ellipse|inset|path|polygon|rect|shape|xywh
      )(\((?:[^()]|\g<1>)*\))
    /x
    UNSAFE_CSS = /[\\(&=}]|\/\*/

    # Port of `wp_kses_no_null()` — wp-includes/kses.php:2019.
    #
    # @param content [String]
    # @return [String]
    def kses_no_null(content)
      content = content.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, '')
      content.gsub(/\\+0+/, '')
    end

    # Port of `wp_kses_decode_entities()` — wp-includes/kses.php:2375.
    #
    # @param content [String]
    # @return [String]
    def kses_decode_entities(content)
      content = content.gsub(/&#([0-9]+);/) { php_chr(Regexp.last_match(1).to_i) }
      content.gsub(/&#[Xx]([0-9A-Fa-f]+);/) { php_chr(Regexp.last_match(1).to_i(16)) }
    end

    # PHP `chr()` — wraps to a single byte. Kept in BINARY encoding because
    # arbitrary byte values are not valid UTF-8; PHP has no such constraint.
    #
    # @param code [Integer]
    # @return [String]
    def php_chr(code)
      (code % 256).chr('BINARY')
    end

    # Port of `wp_kses_bad_protocol_once2()` — wp-includes/kses.php:2136.
    #
    # @param scheme [String]
    # @param allowed_protocols [Array<String>]
    # @return [String]
    def bad_protocol_once2(scheme, allowed_protocols)
      scheme = kses_decode_entities(scheme.dup.force_encoding(Encoding::BINARY))
      scheme = scheme.gsub(/[ \t\r\n\f\v]/, '')
      scheme = kses_no_null(scheme)
      scheme = scheme.downcase

      return '' unless allowed_protocols.any? { |protocol| protocol.downcase(:ascii) == scheme }

      "#{scheme.force_encoding(Encoding::UTF_8)}:"
    end

    # Port of `wp_kses_bad_protocol_once()` — wp-includes/kses.php:2099.
    #
    # @param content [String]
    # @param allowed_protocols [Array<String>]
    # @param count [Integer]
    # @return [String]
    def bad_protocol_once(content, allowed_protocols, count = 1)
      content = content.gsub(/(&#0*58(?![;0-9])|&#x0*3a(?![;a-f0-9]))/i, '\1;')
      parts = content.split(/:|&#0*58;|&#x0*3a;|&colon;/i, 2)

      if parts.length > 1 && parts[0] !~ %r{/\?}
        content = PhpCompat.php_trim(parts[1])
        protocol = bad_protocol_once2(parts[0], allowed_protocols)
        if protocol == 'feed:'
          return '' if count > 2

          content = bad_protocol_once(content, allowed_protocols, count + 1)
          return content if PhpCompat.php_empty?(content)
        end
        content = protocol + content
      end

      content
    end

    # Port of `wp_kses_bad_protocol()` — wp-includes/kses.php:1983.
    #
    # @param content [String]
    # @param allowed_protocols [Array<String>]
    # @return [String]
    def bad_protocol(content, allowed_protocols = ALLOWED_PROTOCOLS)
      content = kses_no_null(content)

      if (content.start_with?('https://') && allowed_protocols.include?('https')) ||
         (content.start_with?('http://') && allowed_protocols.include?('http'))
        return content
      end

      iterations = 0
      original_content = content
      loop do
        original_content = content
        content = bad_protocol_once(content, allowed_protocols)
        iterations += 1
        break unless original_content != content && iterations < 6
      end

      return '' if original_content != content

      content
    end

    # BR-MIGRATE-216 (render half). Port of `safecss_filter_attr()` —
    # wp-includes/kses.php:2647. Returns the semicolon-joined subset of `css`
    # whose declarations are considered safe.
    #
    # @param css [String] a `property: value` list
    # @return [String]
    def safecss_filter_attr(css)
      # `safecss_filter_attr()` carries no /u modifier anywhere, so it is purely
      # byte-oriented; see PhpCompat.as_bytes.
      css = kses_no_null(PhpCompat.as_bytes(css.to_s))
      css = css.gsub(/[\n\r\t]/, '')

      css_array = PhpCompat.php_trim(css).split(';', -1)
      allowed_attr = ALLOWED_ATTR.dup

      out = String.new(encoding: css.encoding)
      css_array.each do |raw_item|
        next if raw_item == ''

        css_item = PhpCompat.php_trim(raw_item)
        css_test_string = css_item
        found = false
        url_attr = false
        gradient_attr = false
        is_custom_var = false
        parts = nil

        if !css_item.include?(':')
          found = true
        else
          parts = css_item.split(':', 2)
          css_selector = PhpCompat.php_trim(parts[0])

          if allowed_attr.include?('--*') && css_selector.match?(CUSTOM_PROPERTY_NAME)
            allowed_attr << css_selector
            is_custom_var = true
          end

          if allowed_attr.include?(css_selector)
            found = true
            url_attr = URL_DATA_TYPES.include?(css_selector)
            gradient_attr = GRADIENT_DATA_TYPES.include?(css_selector)
          end

          if is_custom_var
            css_value = PhpCompat.php_trim(parts[1].to_s)
            url_attr = css_value.start_with?('url(')
            gradient_attr = css_value.include?('-gradient(')
          end
        end

        if found && url_attr
          parts[1].to_s.scan(URL_CALL).each do |url_match|
            url_pieces = URL_PIECES.match(url_match)
            if url_pieces.nil? || PhpCompat.php_empty?(url_pieces[2])
              found = false
              break
            end

            url = PhpCompat.php_trim(url_pieces[2])
            if PhpCompat.php_empty?(url) || bad_protocol(url, ALLOWED_PROTOCOLS) != url
              found = false
              break
            end

            css_test_string = css_test_string.sub(url_match, '')
          end
        end

        if found && gradient_attr
          css_test_string.scan(GRADIENT_CALL).each do |gradient_match|
            css_test_string = css_test_string.sub(gradient_match, '')
          end
        end

        next unless found

        css_test_string = css_test_string.gsub(CSS_FUNCTION_CALL, '')
        allow_css = !css_test_string.match?(UNSAFE_CSS)
        next unless allow_css

        out << ';' unless out.empty?
        out << css_item
      end

      PhpCompat.as_text(out)
    end
  end
end
