# frozen_string_literal: true

module Identity
  # T-10: the target must verify legacy phpass ($P$ / $H$) digests so a corpus user
  # can authenticate once and be transparently rehashed. Port of class-phpass.php's
  # crypt_private() (dependencies.md §3) — the algorithm is fixed and small.
  module PhpassVerifier
    ITOA64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

    module_function

    def verify(password, stored)
      return false if stored.to_s.length < 12

      count_log2 = ITOA64.index(stored[3])
      return false if count_log2.nil? || count_log2 < 7 || count_log2 > 30

      salt = stored[4, 8]
      return false if salt.length != 8

      hash = Digest::MD5.digest(salt + password.to_s)
      (1 << count_log2).times { hash = Digest::MD5.digest(hash + password.to_s) }

      output = stored[0, 12] + encode64(hash, 16)
      # Constant-time comparison: the legacy used a plain ===; this is the one place
      # the port is deliberately stricter, and it is not observable behaviour.
      ActiveSupport::SecurityUtils.secure_compare(output, stored)
    end

    def encode64(input, count)
      output = +""
      i = 0
      while i < count
        value = input.getbyte(i)
        i += 1
        output << ITOA64[value & 0x3f]
        value |= input.getbyte(i) << 8 if i < count
        output << ITOA64[(value >> 6) & 0x3f]
        break if i >= count

        i += 1
        value |= input.getbyte(i) << 16 if i < count
        output << ITOA64[(value >> 12) & 0x3f]
        break if i >= count

        i += 1
        output << ITOA64[(value >> 18) & 0x3f]
      end
      output
    end
  end
end
