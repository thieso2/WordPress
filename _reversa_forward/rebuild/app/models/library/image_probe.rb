# frozen_string_literal: true

module Library
  # Reads intrinsic image dimensions out of the BYTES.
  #
  # AGG-Asset invariant (target_domain_model.md): "MIME type is determined from content,
  # not from the filename extension alone." The same is true of the dimensions the
  # subsize geometry is computed from — the legacy reads them with getimagesize(), which
  # parses the header and never looks at the name. Trusting the extension here would
  # make BR-MIGRATE-079 (never upscale) decidable from a string the uploader chose.
  module ImageProbe
    PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b
    GIF_SIGNATURES = ["GIF87a".b, "GIF89a".b].freeze

    module_function

    # Returns [width, height], or nil when the bytes are not an image this can read.
    def dimensions(bytes)
      data = bytes.to_s.b
      return png(data) if data.start_with?(PNG_SIGNATURE)
      return gif(data) if GIF_SIGNATURES.any? { |sig| data.start_with?(sig) }
      return jpeg(data) if data.start_with?("\xFF\xD8".b)

      nil
    end

    def png(data)
      return nil if data.bytesize < 24

      data[16, 8].unpack("N2")
    end

    def gif(data)
      return nil if data.bytesize < 10

      data[6, 4].unpack("v2")
    end

    # Walks the JPEG marker chain to the first SOFn segment, which is where the frame
    # dimensions live. Anything before it is metadata of one kind or another.
    def jpeg(data)
      offset = 2
      size = data.bytesize

      while offset + 4 <= size
        return nil unless data.getbyte(offset) == 0xFF

        marker = data.getbyte(offset + 1)
        if marker == 0xFF # fill byte padding between segments
          offset += 1
          next
        end

        length = data[offset + 2, 2].unpack1("n").to_i
        # SOF0..SOF15, excluding the four non-frame markers in that range.
        if marker.between?(0xC0, 0xCF) && ![0xC4, 0xC8, 0xCC].include?(marker)
          return nil if offset + 9 > size

          height, width = data[offset + 5, 4].unpack("n2")
          return [width, height]
        end

        return nil if length < 2

        offset += 2 + length
      end

      nil
    end
  end
end
