# frozen_string_literal: true

require "ffi"

module Library
  # PHP's `finfo_file( FILEINFO_MIME_TYPE )` — the non-image half of
  # wp_check_filetype_and_ext() (functions.php:3216). PHP's fileinfo extension is
  # libmagic, so the same library answers here, through FFI, from the same magic
  # database. A content-type verdict is the one place where "close enough" is not:
  # the rejection "Sorry, you are not allowed to upload this file type." hangs on
  # `$type !== $real_mime`, and a sniffer that calls `notes.txt` application/octet-stream
  # where libmagic says text/plain would refuse a file the legacy accepts.
  #
  # Marcel is the fallback when libmagic is not installed; the divergence above is then
  # real and the differential spec reports it rather than hiding it.
  module Fileinfo
    MAGIC_MIME_TYPE = 0x000010
    MUTEX = Mutex.new

    module Binding
      extend FFI::Library
      begin
        ffi_lib %w[libmagic.so.1 magic]
        attach_function :magic_open, [:int], :pointer
        attach_function :magic_load, [:pointer, :string], :int
        attach_function :magic_buffer, [:pointer, :pointer, :size_t], :string
        AVAILABLE = true
      rescue LoadError
        AVAILABLE = false
      end
    end

    module_function

    def libmagic? = Binding::AVAILABLE

    def mime(bytes)
      data = bytes.to_s.b
      return "application/x-empty" if data.empty?
      return Marcel::MimeType.for(StringIO.new(data)) unless libmagic?

      MUTEX.synchronize do
        @cookie ||= Binding.magic_open(MAGIC_MIME_TYPE).tap { |c| Binding.magic_load(c, nil) }
        pointer = FFI::MemoryPointer.new(:char, data.bytesize)
        pointer.put_bytes(0, data)
        Binding.magic_buffer(@cookie, pointer, data.bytesize).to_s
      end
    end
  end
end
