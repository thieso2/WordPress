# frozen_string_literal: true

module Configuration
  # AD-06, the third of the four responsibilities that leave `options`.
  #
  # BR-OPT-08: in the legacy a transient is a pair of rows in the options table —
  # `_transient_<name>` for the value and `_transient_timeout_<name>` for the expiry —
  # which is how a cached value with a TTL came to share a unique index, and a 150 KB
  # autoload heuristic, with the site title and the routing table.
  #
  # Here a cached value with an expiry is a cache entry. It is not a setting, it cannot
  # be written to the settings store (Setting rejects the legacy prefixes), and the
  # discarded rules say why that is not a loss: BR-DISCARD-033..036 retire the
  # autoload-by-presence-of-expiry rule, the lazy expiry sweep, and the missing-timeout
  # repair, because the cache expires its own entries.
  class Transient
    NAMESPACE = "configuration/transient"

    class << self
      def write(name, value, expires_in:)
        Rails.cache.write(key(name), value, expires_in: expires_in)
      end

      def read(name)  = Rails.cache.read(key(name))
      def exist?(name) = Rails.cache.exist?(key(name))
      def delete(name) = Rails.cache.delete(key(name))

      def key(name) = "#{NAMESPACE}/#{name}"
    end
  end
end
