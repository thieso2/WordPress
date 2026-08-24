# frozen_string_literal: true

module Seeding
  # T-02: PHP serialize() -> jsonb.
  #
  # "Scalars (s:, i:, d:, b:, N;) map directly. Arrays (a:) map to JSON objects or
  #  arrays depending on whether keys are a contiguous integer sequence.
  #  **Objects (O:) have no automatic mapping.**"
  #
  # Unparseable payloads and every O: payload go to QUARANTINE preserving the raw bytes.
  # Never discard; never guess a class mapping. (RISK-006)
  #
  # The length prefix on s: is a BYTE count, not a character count. The corpus carries
  # 4-byte UTF-8 on purpose, so this parser works on ASCII-8BIT and re-tags at the end;
  # reading it as characters silently truncates every emoji-bearing string.
  module PhpSerialization
    class ParseError < StandardError; end
    class UnmappableObject < StandardError
      attr_reader :class_name

      def initialize(class_name)
        @class_name = class_name
        super("PHP object payload of class #{class_name.inspect} has no automatic mapping")
      end
    end

    module_function

    # Returns [:scalar | :array | :object | :unserialized, value]
    # A value that is not serialized at all is returned as-is — most option values are
    # plain strings, exactly as maybe_unserialize() treats them.
    def parse(raw)
      return [:unserialized, raw] if raw.nil?

      bytes = raw.dup.force_encoding(Encoding::ASCII_8BIT)
      return [:unserialized, raw] unless serialized?(bytes)

      scanner = Scanner.new(bytes)
      value = scanner.read_value
      scanner.assert_consumed!
      [classify(value), value]
    end

    # Mirrors is_serialized() closely enough for the corpus: a serialized payload starts
    # with a type tag and ends with `;` or `}`.
    # ⚠️ The NULL tag is checked BEFORE the length guard. "N;" is two bytes, so a
    # length-first guard rejects it and the value round-trips as the literal string
    # "N;" instead of nil -- a silent corruption of every NULL meta value in the corpus.
    # Found by spec, not by review.
    def serialized?(bytes)
      return true if bytes == "N;"
      return false if bytes.length < 4

      bytes.match?(/\A[adObis]:/)
    end

    def classify(value)
      case value
      when Hash, ::Array then :array
      else :scalar
      end
    end

    # A recursive-descent reader over the PHP serialization grammar.
    class Scanner
      def initialize(bytes)
        @s = bytes
        @i = 0
      end

      def assert_consumed!
        rest = @s[@i..].to_s
        raise ParseError, "trailing bytes: #{rest.byteslice(0, 40).inspect}" unless rest.empty?
      end

      def read_value
        tag = @s.byteslice(@i, 2)
        case tag
        when "N;" then @i += 2; nil
        when "b:" then read_bool
        when "i:" then read_int
        when "d:" then read_float
        when "s:" then read_string
        when "a:" then read_array
        when "O:" then read_object
        else
          raise ParseError, "unknown type tag #{tag.inspect} at byte #{@i}"
        end
      end

      private

      def expect(char)
        actual = @s.byteslice(@i, 1)
        raise ParseError, "expected #{char.inspect} at byte #{@i}, got #{actual.inspect}" unless actual == char

        @i += 1
      end

      def read_until(char)
        stop = @s.index(char, @i)
        raise ParseError, "unterminated token at byte #{@i}" if stop.nil?

        token = @s.byteslice(@i, stop - @i)
        @i = stop + 1
        token
      end

      def read_bool
        @i += 2
        token = read_until(";")
        token == "1"
      end

      def read_int
        @i += 2
        Integer(read_until(";"))
      end

      def read_float
        @i += 2
        token = read_until(";")
        case token
        when "NAN" then Float::NAN
        when "INF" then Float::INFINITY
        when "-INF" then -Float::INFINITY
        else Float(token)
        end
      end

      # s:<byte length>:"<bytes>";  — the length is BYTES.
      def read_string
        @i += 2
        length = Integer(read_until(":"))
        expect('"')
        value = @s.byteslice(@i, length)
        raise ParseError, "string shorter than its declared length at byte #{@i}" if value.nil? || value.bytesize < length

        @i += length
        expect('"')
        expect(";")
        # Re-tag as UTF-8: the bytes were always UTF-8, only the arithmetic was binary.
        value.dup.force_encoding(Encoding::UTF_8)
      end

      # a:<count>:{<key><value>...}
      # Maps to a JSON array when the keys are a contiguous 0..n-1 integer sequence,
      # and to a JSON object otherwise — PHP's own array/list duality.
      def read_array
        @i += 2
        count = Integer(read_until(":"))
        expect("{")
        pairs = Array.new(count) do
          key = read_value
          [key, read_value]
        end
        expect("}")

        keys = pairs.map(&:first)
        if keys.each_with_index.all? { |k, idx| k.is_a?(Integer) && k == idx }
          pairs.map(&:last)
        else
          pairs.to_h { |k, v| [k.to_s, v] }
        end
      end

      # O:<len>:"<class>":<count>:{...} — no automatic mapping, by rule.
      def read_object
        @i += 2
        length = Integer(read_until(":"))
        expect('"')
        class_name = @s.byteslice(@i, length).dup.force_encoding(Encoding::UTF_8)
        @i += length
        expect('"')
        raise UnmappableObject, class_name
      end
    end
  end
end
