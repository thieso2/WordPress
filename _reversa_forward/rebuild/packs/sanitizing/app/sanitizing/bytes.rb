# frozen_string_literal: true

module Sanitizing
  # Byte-string discipline for the whole pack.
  #
  # RISK-005 / handoff.md item 3. None of the ported PCRE patterns carry the `/u`
  # modifier, so in PHP every one of them runs over *bytes*, not characters. Ruby
  # regexps run over characters and raise `ArgumentError` the moment the subject
  # is not valid in its declared encoding, which would turn a malformed-input case
  # (exactly the case KSES exists for) into a 500 instead of a sanitized string.
  #
  # Therefore every entry point converts to ASCII-8BIT on the way in and back to
  # UTF-8 on the way out. This reproduces PCRE's byte semantics exactly, including
  # `\s`, `[a-z]` and `/i` being ASCII-only, and it makes invalid UTF-8 inert
  # rather than fatal.
  module Bytes
    module_function

    # Enter the byte domain. Legacy equivalent: nothing — PHP strings are bytes.
    def binary(str)
      str = str.to_s
      str.encoding == Encoding::BINARY ? str : str.dup.force_encoding(Encoding::BINARY)
    end

    # Leave the byte domain. Output is tagged UTF-8 without validation, matching
    # PHP, which also hands back whatever bytes it produced.
    def utf8(str)
      str.dup.force_encoding(Encoding::UTF_8)
    end

    # PCRE's `$` with no `/m` and no `/D`: end of subject, or immediately before a
    # newline that ends the subject. Ruby's `$` is a *line* anchor and `\z` forbids
    # the trailing newline, so neither is a correct substitute on its own.
    # Getting this wrong is the documented way to turn an allowlist into a bypass.
    PCRE_EOS = '(?=\n?\z)'

    # PCRE's `^` with no `/m`: start of subject. Ruby's `^` is a line anchor.
    PCRE_BOS = '\A'

    # Builds a regexp in the byte domain.
    #
    # ⚠️ Not cosmetic. A Ruby regexp whose *source* is a UTF-8 string containing
    # a `\xNN` escape above 0x7F becomes a fixed-encoding UTF-8 regexp, and such
    # a regexp raises Encoding::CompatibilityError the moment it meets a binary
    # subject. `wp_spaces_regexp()` (wp-includes/formatting.php:5960) contains
    # exactly that: `\xC2\xA0`. Forcing the source to ASCII-8BIT gives a
    # byte-oriented regexp, which is what PCRE compiled in the first place.
    def regexp(source, options = nil)
      Regexp.new(binary(source), options)
    end
  end
end
