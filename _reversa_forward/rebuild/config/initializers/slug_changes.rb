# frozen_string_literal: true

# The two remaining Publishing -> Routing ports, wired at boot exactly as
# reserved_segments.rb wires the first. Publishing owns the interfaces
# (`Publishing.slug_allocator`, `Publishing.slug_change_recorder`); Routing supplies
# the implementations, so the arrow stays Routing -> Publishing and bin/check_cycles
# still sees a DAG (target_architecture.md Note 2).
#
# Not a hook: one implementation, fixed at boot, with no API to add another. AD-01 bars
# a chain that can change an outcome at runtime; this cannot.
Rails.application.config.to_prepare do
  # BR-MIGRATE-032..035: first publication allocates a slug that is unique within the
  # record's scope and clears the reserved set. `allocate` proposes; the record's own
  # save persists it, so the unique index remains the guarantee (AD-05).
  Publishing.slug_allocator = lambda do |record, requested|
    Routing::SlugAllocator.new.allocate(record, requested: requested)
  end

  # AD-03: `_wp_old_slug` becomes a Routing::Redirect row (target_domain_model.md
  # AGG-Permalink). wp_check_for_changed_slugs() (wp-includes/post.php:7567) also
  # DELETES the old-slug entry that matches the slug a record is renamed BACK to, so the
  # record never redirects to itself; the same is done here on the path now occupied.
  Publishing.slug_change_recorder = lambda do |record, old_slug|
    structure = Routing::PermalinkStructure.current
    Routing::Redirect.record_slug_change!(record, old_slug, structure: structure)
    Routing::Redirect.where(from_path: structure.path_for(record)).delete_all
  end
end
