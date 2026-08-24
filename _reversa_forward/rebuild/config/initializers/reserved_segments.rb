# frozen_string_literal: true

# BR-MIGRATE-034's inverted dependency, wired at boot.
#
# Publishing owns the interface (`Publishing.reserved_segment_source`); Routing supplies
# the implementation. The arrow therefore stays Routing -> Publishing, and the namespace
# graph stays acyclic -- see bin/check_cycles and target_architecture.md Note 2.
#
# Declaring it here rather than inside Publishing::Post is the whole point: the model
# must not name Routing. If this initializer is deleted, slug validation silently stops
# consulting the reserved set -- so a parity test asserts the wiring, not just the rule.
Rails.application.config.to_prepare do
  Publishing.reserved_segment_source = -> { Routing::PermalinkStructure.current.reserved_segments }
end
