# frozen_string_literal: true

module Access
  # BC-06 -- "the load-bearing extraction of the whole design."
  #
  # In the legacy, map_meta_cap('edit_post') reads the post while posts carry
  # post_author: a mutual dependency that is one of the surviving edges of the 23-module
  # cycle. Lifting policy into a context ABOVE both models converts that cycle into a
  # DAG. Access depends on Identity, Publishing, Discussion, Classification, Library and
  # Configuration; NONE OF THEM DEPENDS ON ACCESS. Only a delivery surface may reference
  # this namespace, and only bin/check_cycles will notice if that stops being true.
  #
  # =========================================================================
  # OWNER OVERRIDE 1 -- the permissive defaults are REPRODUCED, deliberately.
  # =========================================================================
  # Question Q4 set "fail closed everywhere" as the house style. At the post-Curator
  # pause the owner ruled the opposite and REAFFIRMED it when the conflict was put to
  # them directly. Finding F-DOM-02 -- which confidence-report.md called the
  # highest-value security observation in the whole analysis -- is knowingly carried
  # into this greenfield system:
  #
  #   BR-CAP-05   a policy method emitting NO capabilities ALLOWS
  #   BR-REST-05  a route registered with NO policy is PUBLIC
  #   BR-ADM-07   an endpoint registered as nopriv-equivalent has NO gate at all
  #
  # AD-01 makes this PERMANENT: with no hook system there is no filter to correct it
  # later. This is uncomfortable to read and it is correct -- parity_tests/04 asserts
  # this behaviour as the specification.
  #
  # AD-04 is the mitigation, and note precisely what it does: it does NOT change the
  # runtime default. It removes the way that default gets REACHED, which is by someone
  # forgetting. Declaration is mandatory; what you declare may be `public`.
  #
  # The evaluation below is WP_User::has_cap() (wp-includes/class-wp-user.php:788-812)
  # with the `user_has_cap` filter removed (AD-01): every policy is one arm of
  # map_meta_cap() (wp-includes/capabilities.php:45) and this class is the part that
  # turns the emitted primitive list into a yes or a no.
  class BasePolicy
    class UndeclaredAuthorization < StandardError; end

    # BR-MIGRATE-098 (BR-CAP-02), class-wp-user.php:806: `do_not_allow` is unset from
    # the user's capability set before evaluation, so a requirement for it can never be
    # satisfied. It is the deny primitive, and the ONLY way a policy can fail closed.
    DO_NOT_ALLOW = "do_not_allow"

    # BR-MIGRATE-100 (BR-CAP-04), class-wp-user.php:805: "Everyone is allowed to exist."
    # Held by every actor, including the anonymous one (user_can(0, 'exist') is true).
    EXIST = "exist"

    attr_reader :actor, :record

    def initialize(actor, record)
      @actor = actor
      @record = record
    end

    # BR-CAP-05, reproduced. An empty capability set ALLOWS.
    #
    # Read that twice: `required_capabilities` returning [] is not "no permission", it is
    # "no requirement". The legacy's map_meta_cap() returns an empty array for an unknown
    # capability and current_user_can() then finds nothing to fail against.
    #
    # BR-MIGRATE-097 (BR-CAP-01), class-wp-user.php:808: has_cap() requires ALL mapped
    # capabilities, not any one of them -- `array_all`, reproduced as `all?`.
    def permit?(action)
      capabilities = Array(required_capabilities(action))
      return true if capabilities.empty?

      # BR-MS-05 (BR-MIGRATE-360) / BR-CAP-03 (BR-MIGRATE-099): a multisite super admin sits
      # ABOVE the role system and "bypasses every capability check except do_not_allow"
      # (class-wp-user.php:795). Membership is the `site_admins` network option, NOT the
      # discarded `$super_admins` global (BR-CAP-14) — Tenancy owns that decision. This is
      # multisite-only and strictly additive: `Tenancy.super_admin?` is false on a single
      # site (Tenancy.enabled? == false), so Waves 0–4 evaluate exactly as before — the
      # ordinary role check below is reached unchanged. do_not_allow still denies, because it
      # is the one primitive even a super admin cannot satisfy (BR-CAP-02).
      return !capabilities.include?(DO_NOT_ALLOW) if Tenancy.super_admin?(actor)

      capabilities.all? { |capability| actor_holds?(capability) }
    end

    # Subclasses override. Returning [] means "allowed" -- see BR-CAP-05 above.
    def required_capabilities(_action) = []

    private

    # One primitive capability against the actor's stored roles.
    #
    # ⚠️ BR-MIGRATE-099 (BR-CAP-03) is NOT here: the multisite super-admin bypass is a
    # Wave 5 concern, and BR-CAP-14's `$super_admins` configuration was DISCARDED as a
    # privilege-escalation vector (discard_log.md section 4). Nothing outranks the rows.
    def actor_holds?(capability)
      name = capability.to_s
      return true if name == EXIST
      return false if name == DO_NOT_ALLOW

      Access::RoleCatalogue.capabilities_for(actor_roles).include?(name)
    end

    def actor_roles
      return [] if actor.nil?

      # BR-CAP-14, DISCARDED at the Curator pause as a privilege-escalation vector:
      # the legacy's $super_admins global outranks the database. Here the stored
      # RoleAssignment rows are the only source, and configuration cannot outrank them.
      # discard_log.md section 4.
      #
      # BR-MS-04 per-site role ENFORCEMENT (strictly additive, mirrors line 77's
      # Tenancy.super_admin? edge — Access already depends on Tenancy, and Tenancy
      # never depends on Access, so no cycle). On a single site Tenancy.current_site
      # is nil (Tenancy.enabled? == false), so this resolves to actor.roles with a
      # nil site_id — byte-identical to Waves 0-4. Under multisite it reads the roles
      # scoped to the site being served, matching WordPress's per-blog
      # wp_{blog_id}_capabilities (WP_User::for_site). Network-level authority is a
      # separate concern already handled by Tenancy.super_admin? at line 77.
      site = Tenancy.current_site
      return actor.roles(site_id: site.id) if site

      actor.roles
    end

    # `$user_id` as map_meta_cap() sees it: 0 for the anonymous visitor. Several arms
    # branch on `$user_id < 1` (BR-MIGRATE-102) and on `$user_id === (int) $args[0]`.
    def actor_id = actor.nil? ? 0 : actor.id.to_i

    # is_super_admin() on a SINGLE site, wp-includes/capabilities.php:1193: a user who
    # holds `delete_users` is a super admin. That is the whole definition here -- the
    # multisite branch reads the `$super_admins` global, which BR-CAP-14 discarded.
    def super_admin?
      actor.present? && actor_holds?("delete_users")
    end

    # `get_option()` for the post-id settings map_meta_cap() consults. Stored as the
    # target's integer id by lib/seeding/pipeline.rb (POST_ID_SETTINGS), `false` when
    # unset -- which `to_i` turns into 0, the legacy's own "no page" value.
    def setting_id(name)
      value = Configuration::Setting[name]
      value == false ? 0 : value.to_i
    end
  end
end
