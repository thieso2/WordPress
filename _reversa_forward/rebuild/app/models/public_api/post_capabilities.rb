# frozen_string_literal: true

module PublicApi
  # What the CONTROLLER already decided about this actor and this record, handed to the
  # serialiser as data.
  #
  # ⚠️ BR-CAP-05's structural half: the controller is the only layer permitted to touch
  # Access (target_architecture.md Note 2, enforced by bin/check_cycles). But
  # `prepare_item_for_response` genuinely needs six capability answers — `targetHints.allow`
  # is the set of verbs THIS caller may use on the record, and `get_available_actions()`
  # (class-wp-rest-posts-controller.php:2341) emits one `wp:action-*` link per capability
  # the caller holds. The legacy could call current_user_can() from inside the serialiser
  # because it had a global current user; here the answers travel explicitly, in this
  # object, decided one layer up.
  #
  # `none` is the anonymous caller: every answer false, which is what an unauthenticated
  # read of a published post gets (`targetHints: { allow: ["GET"] }`, no action links).
  PostCapabilities = Struct.new(:edit, :delete, :publish, :unfiltered_html, :edit_others,
                                :create_categories, :assign_categories,
                                :create_tags, :assign_tags, keyword_init: true) do
    def self.none = new(**members.index_with(false))

    # class-wp-rest-server.php's target hints: the verbs the route offers that this caller
    # would actually be allowed to invoke. GET is always there (the read gate already let
    # the record through); the write verbs follow the edit/delete arms of map_meta_cap().
    def allowed_methods
      allow = %w[GET]
      allow.concat(%w[POST PUT PATCH]) if edit
      allow << "DELETE" if delete
      allow
    end
  end
end
