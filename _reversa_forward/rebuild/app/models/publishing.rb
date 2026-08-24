# frozen_string_literal: true

# Publishing — bounded context (BC-01). A Ruby namespace, not a pack:
# topology_decision.md option 3 keeps the content core as conventional Rails.
#
# ── The three ports below are ONE pattern, and it is not a hook system ──────────
# Each is a boot-time dependency inversion with exactly one implementation, supplied by
# config/initializers/reserved_segments.rb and config/initializers/slug_changes.rb. They
# exist because Routing -> Publishing is the permitted edge (target_architecture.md Note
# 2) and Publishing may not name Routing, yet three of AGG-Post's invariants need what
# only Routing knows: the reserved route segments, how to allocate a slug that clears
# them, and where a renamed record USED to live. AD-01 forbids a runtime-extensible
# chain that can change an outcome; a fixed port with one implementation cannot — it is
# configuration, not per-request state (paradigm_decision.md implication 1).
module Publishing
  # BR-MIGRATE-034's inverted dependency. Publishing declares what it needs to know;
  # Routing fills it in at boot. Publishing therefore depends on nothing, and the
  # Routing -> Publishing arrow in target_architecture.md's graph stays the only one.
  # Configuration, not per-request state — implication 1 forbids the latter, not this.
  mattr_accessor :reserved_segment_source, default: -> { [] }

  # BR-MIGRATE-032/033/034: first publication allocates a slug (wp-includes/post.php:5047,
  # `if ( empty( $data['post_name'] ) && ! in_array( $data['post_status'], array(
  # 'draft', 'pending', 'auto-draft' ) ) )`), and only Routing can propose one that is
  # unique AND clears the reserved set. Receives (record, requested) and returns the
  # slug to use, or nil when nothing can be derived. Does not save.
  mattr_accessor :slug_allocator, default: ->(_record, _requested) { nil }

  # AD-03: replaces `wp_check_for_changed_slugs()` (wp-includes/post.php:7567), which
  # stored `_wp_old_slug` postmeta. Receives (record, old_slug) after a published,
  # non-hierarchical record's slug has changed; Routing records the redirect, because
  # only Routing knows which PATH the old slug produced.
  mattr_accessor :slug_change_recorder, default: ->(_record, _old_slug) { nil }

  def self.reserved_segments
    Array(reserved_segment_source.call).map(&:to_s).to_set
  end
end
