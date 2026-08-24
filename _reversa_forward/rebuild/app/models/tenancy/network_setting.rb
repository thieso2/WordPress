# frozen_string_literal: true

module Tenancy
  # Site/network options (BR-MS-08 / BR-MIGRATE-363): the legacy split these across
  # `wp_blogmeta` (per-site) and `wp_sitemeta` (network-wide). AD-06 already broke
  # `wp_options`' four jobs apart for the single site; the network layer gets the same
  # treatment — a narrow, global key/value settings store, NOT a meta table. This is the
  # NETWORK-wide half (wp_sitemeta); the per-site half (wp_blogmeta) is just
  # Configuration::Setting inside each tenant schema, so it needs nothing new.
  #
  # Lives in the global schema, keyed by name. Value is jsonb so a list (site_admins) or a
  # scalar (registration mode) round-trips without the legacy's serialize()/maybe_unserialize().
  class NetworkSetting < ApplicationRecord
    self.table_name = "network_settings"

    validates :name, presence: true, uniqueness: true

    class << self
      def [](name)
        find_by(name: name.to_s)&.value
      end

      def []=(name, value)
        record = find_or_initialize_by(name: name.to_s)
        record.value = value
        record.save!
        value
      end

      # BR-CAP-14 / BR-DISCARD-046: get_super_admins() preferred the `$super_admins` PHP
      # GLOBAL over this network option. The global was discarded as a privilege-escalation
      # vector (discard_log.md §4), so the `site_admins` option is the ONLY source of
      # super-admin membership — configuration can no longer outrank the stored list.
      # Stored as an array of user ids; empty when unset (no super admins ⇒ nobody bypasses).
      def super_admin_ids
        Array(self["site_admins"]).map { |id| Integer(id) }
      rescue ArgumentError, TypeError
        []
      end
    end
  end
end
