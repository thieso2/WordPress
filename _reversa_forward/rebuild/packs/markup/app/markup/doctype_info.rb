# frozen_string_literal: true

module Markup
  # Parsed contents of a DOCTYPE declaration.
  #
  # The Tag Processor only finds the *shape* of a DOCTYPE while scanning; this class does
  # the detailed parse on demand. The HTML Processor needs exactly one thing from it —
  # `indicated_compatibility_mode` — because a quirks-mode document changes how class
  # names are matched and whether an open `P` is closed by a `TABLE` (BR-MIGRATE-223).
  #
  # Legacy: wp-includes/html-api/class-wp-html-doctype-info.php:2.
  class DoctypeInfo
    WHITESPACE = " \t\n\f\r"

    # Public identifiers that force quirks mode outright (exact match, lowercased).
    QUIRKS_EXACT_PUBLIC_IDENTIFIERS = [
      "-//w3o//dtd w3 html strict 3.0//en//",
      "-/w3c/dtd html 4.0 transitional/en",
      "html"
    ].freeze

    QUIRKS_SYSTEM_IDENTIFIER = "http://www.ibm.com/data/dtd/v11/ibmxhtml1-transitional.dtd"

    # Public-identifier prefixes that force quirks mode.
    QUIRKS_PUBLIC_IDENTIFIER_PREFIXES = [
      "+//silmaril//dtd html pro v0r11 19970101//",
      "-//as//dtd html 3.0 aswedit + extensions//",
      "-//advasoft ltd//dtd html 3.0 aswedit + extensions//",
      "-//ietf//dtd html 2.0 level 1//",
      "-//ietf//dtd html 2.0 level 2//",
      "-//ietf//dtd html 2.0 strict level 1//",
      "-//ietf//dtd html 2.0 strict level 2//",
      "-//ietf//dtd html 2.0 strict//",
      "-//ietf//dtd html 2.0//",
      "-//ietf//dtd html 2.1e//",
      "-//ietf//dtd html 3.0//",
      "-//ietf//dtd html 3.2 final//",
      "-//ietf//dtd html 3.2//",
      "-//ietf//dtd html 3//",
      "-//ietf//dtd html level 0//",
      "-//ietf//dtd html level 1//",
      "-//ietf//dtd html level 2//",
      "-//ietf//dtd html level 3//",
      "-//ietf//dtd html strict level 0//",
      "-//ietf//dtd html strict level 1//",
      "-//ietf//dtd html strict level 2//",
      "-//ietf//dtd html strict level 3//",
      "-//ietf//dtd html strict//",
      "-//ietf//dtd html//",
      "-//metrius//dtd metrius presentational//",
      "-//microsoft//dtd internet explorer 2.0 html strict//",
      "-//microsoft//dtd internet explorer 2.0 html//",
      "-//microsoft//dtd internet explorer 2.0 tables//",
      "-//microsoft//dtd internet explorer 3.0 html strict//",
      "-//microsoft//dtd internet explorer 3.0 html//",
      "-//microsoft//dtd internet explorer 3.0 tables//",
      "-//netscape comm. corp.//dtd html//",
      "-//netscape comm. corp.//dtd strict html//",
      "-//o'reilly and associates//dtd html 2.0//",
      "-//o'reilly and associates//dtd html extended 1.0//",
      "-//o'reilly and associates//dtd html extended relaxed 1.0//",
      "-//sq//dtd html 2.0 hotmetal + extensions//",
      "-//softquad software//dtd hotmetal pro 6.0::19990601::extensions to html 4.0//",
      "-//softquad//dtd hotmetal pro 4.0::19971010::extensions to html 4.0//",
      "-//spyglass//dtd html 2.0 extended//",
      "-//sun microsystems corp.//dtd hotjava html//",
      "-//sun microsystems corp.//dtd hotjava strict html//",
      "-//w3c//dtd html 3 1995-03-24//",
      "-//w3c//dtd html 3.2 draft//",
      "-//w3c//dtd html 3.2 final//",
      "-//w3c//dtd html 3.2//",
      "-//w3c//dtd html 3.2s draft//",
      "-//w3c//dtd html 4.0 frameset//",
      "-//w3c//dtd html 4.0 transitional//",
      "-//w3c//dtd html experimental 19960712//",
      "-//w3c//dtd html experimental 970421//",
      "-//w3c//dtd w3 html//",
      "-//w3o//dtd w3 html 3.0//",
      "-//webtechs//dtd mozilla html 2.0//",
      "-//webtechs//dtd mozilla html//"
    ].freeze

    HTML_4_01_PREFIXES = [
      "-//w3c//dtd html 4.01 frameset//",
      "-//w3c//dtd html 4.01 transitional//"
    ].freeze

    XHTML_1_0_PREFIXES = [
      "-//w3c//dtd xhtml 1.0 frameset//",
      "-//w3c//dtd xhtml 1.0 transitional//"
    ].freeze

    attr_reader :name, :public_identifier, :system_identifier, :indicated_compatibility_mode

    # Parses the raw text of a DOCTYPE token, or returns nil when it is not one.
    #
    # BR-MIGRATE-223 (quirks mode feeds tree construction).
    # Legacy: class-wp-html-doctype-info.php:from_doctype_token.
    def self.from_doctype_token(doctype_html) # rubocop:disable Metrics/AbcSize
      doctype_html = doctype_html.b
      name = nil
      public_id = nil
      system_id = nil

      last = doctype_html.bytesize - 1
      return nil if last < 9
      return nil unless doctype_html.byteslice(0, 9).downcase == "<!doctype"

      at = 9
      return nil if doctype_html.getbyte(last) != 0x3E # `>`
      return nil if ByteScan.cspan(doctype_html, ">", at) + at < last

      doctype_html = doctype_html.gsub("\r\n", "\n").gsub("\r", "\n")
      last = doctype_html.bytesize - 1

      at += ByteScan.span(doctype_html, WHITESPACE, at)
      return new(name, public_id, system_id, true) if at >= last

      name_length = ByteScan.cspan(doctype_html, WHITESPACE, at, last - at)
      name = doctype_html.byteslice(at, name_length).downcase.gsub("\x00", Decoder::REPLACEMENT_CHARACTER)
      at += name_length

      at += ByteScan.span(doctype_html, WHITESPACE, at, last - at)
      return new(name, public_id, system_id, false) if at >= last
      return new(name, public_id, system_id, true) if at + 6 >= last

      keyword = doctype_html.byteslice(at, 6).downcase
      if keyword == "public"
        at += 6
        at += ByteScan.span(doctype_html, WHITESPACE, at, last - at)
        return new(name, public_id, system_id, true) if at >= last

        public_id, at, failed = read_quoted(doctype_html, at, last)
        return new(name, public_id, system_id, true) if failed

        at += ByteScan.span(doctype_html, WHITESPACE, at, last - at)
        return new(name, public_id, system_id, false) if at >= last
      elsif keyword == "system"
        at += 6
        at += ByteScan.span(doctype_html, WHITESPACE, at, last - at)
        return new(name, public_id, system_id, true) if at >= last
      else
        return new(name, public_id, system_id, true)
      end

      system_id, _at, failed = read_quoted(doctype_html, at, last)
      new(name, public_id, system_id, failed)
    end

    # Reads a quoted identifier; returns [value, next_offset, failed].
    def self.read_quoted(doctype_html, at, last)
      closer_quote = doctype_html.byteslice(at, 1)
      return [nil, at, true] if closer_quote != '"' && closer_quote != "'"

      at += 1
      identifier_length = ByteScan.cspan(doctype_html, closer_quote, at, last - at)
      value = doctype_html.byteslice(at, identifier_length).gsub("\x00", Decoder::REPLACEMENT_CHARACTER)
      at += identifier_length
      return [value, at, true] if at >= last || doctype_html.byteslice(at, 1) != closer_quote

      [value, at + 1, false]
    end
    private_class_method :read_quoted

    def initialize(name, public_identifier, system_identifier, force_quirks_flag)
      @name = name
      @public_identifier = public_identifier
      @system_identifier = system_identifier
      @indicated_compatibility_mode = compute_mode(name, public_identifier, system_identifier,
                                                   force_quirks_flag)
    end

    private

    def compute_mode(name, public_identifier, system_identifier, force_quirks_flag) # rubocop:disable Metrics/AbcSize
      return "quirks" if force_quirks_flag
      return "no-quirks" if name == "html" && public_identifier.nil? && system_identifier.nil?
      return "quirks" if name != "html"

      public_identifier = public_identifier.nil? ? "" : public_identifier.downcase
      system_identifier = system_identifier.nil? ? "" : system_identifier.downcase

      return "quirks" if QUIRKS_EXACT_PUBLIC_IDENTIFIERS.include?(public_identifier)
      return "quirks" if system_identifier == QUIRKS_SYSTEM_IDENTIFIER
      return "no-quirks" if public_identifier == ""
      return "quirks" if QUIRKS_PUBLIC_IDENTIFIER_PREFIXES.any? { |p| public_identifier.start_with?(p) }

      html_4_01 = HTML_4_01_PREFIXES.any? { |p| public_identifier.start_with?(p) }
      return "quirks" if system_identifier == "" && html_4_01
      return "limited-quirks" if XHTML_1_0_PREFIXES.any? { |p| public_identifier.start_with?(p) }
      return "limited-quirks" if system_identifier != "" && html_4_01

      "no-quirks"
    end
  end
end
