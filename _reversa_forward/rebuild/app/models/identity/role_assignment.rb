# frozen_string_literal: true

module Identity
  # T-03: the legacy stored this as usermeta['{prefix}capabilities'], a serialized
  # `role => true` map (F-MS-04, BR-CAP-13). Under multisite the prefix encodes the
  # site (wp_capabilities, wp_3_capabilities, ...), so site_id is parsed out of the key.
  #
  # ⚠️ {prefix}user_level (BR-CAP-11) is NOT migrated: level_0..level_10 exist in every
  # role only for backward compatibility with plugins that still test for them
  # (TD-17, ADR-002) — a compatibility burden migration_brief.md has deleted.
  class RoleAssignment < ApplicationRecord
    self.table_name = "role_assignments"
    belongs_to :user, class_name: "Identity::User"
    validates :role, presence: true, uniqueness: { scope: %i[user_id site_id] }
  end
end
