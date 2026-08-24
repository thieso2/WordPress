# frozen_string_literal: true

module Access
  # The user arms of map_meta_cap(), wp-includes/capabilities.php:49-80 and :673-690.
  # `record` is the Identity::User being acted on; it may be nil for `create` and `list`.
  #
  # ⚠️ Every multisite branch -- BR-MIGRATE-104 (manage_network_users), BR-MIGRATE-105
  # (removing oneself as a non-super-admin) -- is left for Wave 5. On a single site
  # is_super_admin() means "holds delete_users" (capabilities.php:1193), and that is the
  # reading used for `remove`.
  class UserPolicy < BasePolicy
    def required_capabilities(action)
      case action.to_sym
      when :read, :list then ["list_users"]
      when :edit        then edit_user
      when :delete      then ["delete_users"]        # :673-680: delete_user -> delete_users
      when :promote     then ["promote_users"]       # :57-59:   promote_user -> promote_users
      when :remove      then remove_user
      when :create      then ["create_users"]        # :682-690, single-site branch
      else []
      end
    end

    private

    # :61-80.
    def edit_user
      # BR-MIGRATE-102 (BR-CAP-06): "Non-existent users can't edit users, not even
      # themselves."
      return [DO_NOT_ALLOW] if actor_id < 1

      # BR-MIGRATE-103 (BR-CAP-07): "Allow user to edit themselves." -- an EMPTY set,
      # which BR-CAP-05 turns into an allow with no requirement at all.
      return [] if self?

      ["edit_users"] # :77: edit_user maps to edit_users.
    end

    # :49-56. "In multisite the user must be a super admin to remove themselves." On a
    # single site the same test reads `holds delete_users`, so an administrator may and
    # nobody else may -- which is what the oracle answers (user_can(1,'remove_user',1)
    # is true, user_can(3,'remove_user',3) is false).
    def remove_user
      return [DO_NOT_ALLOW] if self? && !super_admin?

      ["remove_users"]
    end

    def self?
      actor.present? && record.respond_to?(:id) && record.id == actor.id
    end
  end
end
