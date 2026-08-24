# frozen_string_literal: true

module Markup
  # UTF-8 predicates the HTML API needs but which live outside html-api in the legacy.
  #
  # Legacy origin: wp-includes/utf8.php:158 (`wp_has_noncharacters()`), pulled in here
  # because `set_attribute()` calls it and this pack declares zero dependencies
  # (topology_decision.md option 3).
  module Utf8
    # The legacy matches raw UTF-8 byte sequences rather than using PCRE's Unicode
    # mode, precisely so that malformed UTF-8 elsewhere in the subject cannot make the
    # whole match fail. That byte-level pattern transfers to Onigmo unchanged; the only
    # adaptation is the `n` (ASCII-8BIT) flag plus matching against `String#b`, which
    # keeps Ruby from re-interpreting `\xEF` as a character in the subject's encoding.
    NONCHARACTERS = /
      # U+FDD0-U+FDEF, U+FFFE-U+FFFF
      \xEF(?:\xB7[\x90-\xAF]|\xBF[\xBE\xBF])
      |
      # U+nFFFE and U+nFFFF
      (?:\xF0[\x9F\xAF\xBF]|[\xF1-\xF3][\x8F\x9F\xAF\xBF]|\xF4\x8F)\xBF[\xBE\xBF]
    /xn
    private_constant :NONCHARACTERS

    # Whether the string contains any Unicode noncharacter.
    #
    # BR-MIGRATE-220 (attribute-name validation in `set_attribute`).
    # Legacy: wp-includes/utf8.php:158.
    def self.noncharacters?(text)
      !NONCHARACTERS.match(text.b).nil?
    end
  end
end
