# frozen_string_literal: true

module Routing
  # BR-MIGRATE-033/034/035. Replaces wp_unique_post_slug()'s one-query-per-attempt loop
  # (F-POST-03) -- but note what is and is not replaced.
  #
  # AD-05 makes the DATABASE the guarantee: a partial unique index on
  # (type, coalesce(parent_id, 0), slug) WHERE slug IS NOT NULL. This class is not that
  # guarantee; it is the allocator that proposes a slug the constraint will accept, and
  # it must be prepared for the constraint to reject its proposal anyway under
  # concurrency. That is why `allocate!` retries on ActiveRecord::RecordNotUnique rather
  # than trusting its own SELECT -- the legacy's check-then-act race is not reproduced.
  #
  # Lives in Routing because only Routing knows the reserved set
  # (target_domain_model.md AGG-Post). Routing -> Publishing is the permitted edge.
  class SlugAllocator
    # BR-MIGRATE-035: 200 bytes INCLUDING any numeric suffix. Bytes, not characters --
    # the corpus carries 4-byte UTF-8, where the difference is a factor of four.
    MAX_BYTES = Publishing::Post::SLUG_MAX_BYTES
    MAX_ATTEMPTS = 1_000

    def initialize(structure: PermalinkStructure.current)
      @structure = structure
    end

    attr_reader :structure

    # BR-MIGRATE-034 is not just set membership: a pagination NUMBER and a date-archive
    # segment are shapes, not names. The structure answers for all four cases.
    def reserved?(slug) = @structure.reserved?(slug)

    # Returns a slug unique within the record's (type, parent) scope that is not a
    # reserved route segment. Does NOT save.
    def allocate(record, requested: nil)
      base = normalize(requested.presence || record.slug.presence || record.title)
      return nil if base.empty?

      candidate = truncate(base, suffix: nil)
      return candidate unless taken?(record, candidate) || reserved?(candidate)

      (2..MAX_ATTEMPTS).each do |n|
        candidate = truncate(base, suffix: n)
        return candidate unless taken?(record, candidate) || reserved?(candidate)
      end
      raise "could not allocate a unique slug for #{base.inspect} after #{MAX_ATTEMPTS} attempts"
    end

    # Allocate and save, retrying if the unique index rejects the proposal -- the
    # constraint, not this class, is the source of truth (AD-05).
    def allocate!(record, requested: nil)
      attempts = 0
      begin
        record.slug = allocate(record, requested: requested)
        record.save!
        record
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        raise if attempts > 5

        retry
      end
    end

    # Accepted command `record_redirect` (target_domain_model.md AGG-Permalink), joined to
    # the rename that causes it. Renaming a published record is a ROUTING operation: the
    # new slug must clear the reserved set and the old PATH has to keep resolving, and
    # only Routing knows either. Publishing owns no reference to Routing, so the rename
    # cannot live on Publishing::Post without re-forming the users<->posts-shaped cycle
    # that target_architecture.md Note 2 exists to prevent.
    def rename!(record, requested:)
      old_slug = record.slug
      record.transaction do
        record.slug = allocate(record, requested: requested)
        record.save!
        Redirect.record_slug_change!(record, old_slug, structure: @structure)
      end
      record
    end

    private

    # WordPress's sanitize_title_with_dashes, for the ASCII path. Non-ASCII is preserved
    # rather than transliterated: the legacy only strips accents when the locale asks,
    # and the corpus deliberately carries 4-byte UTF-8 slugs.
    PUNCTUATION = %r{['"!#$%&()*+,./:;<=>?@\[\\\]^`{|}~]}

    def normalize(value)
      value.to_s
           .unicode_normalize(:nfc)
           .downcase
           .gsub(/[\s_]+/, "-")
           .gsub(PUNCTUATION, "")
           .gsub(/-+/, "-")
           .gsub(/\A-+|-+\z/, "")
    end

    # The boundary the legacy gets right and a naive port gets wrong: the suffix is
    # inside the budget, so the BASE is shortened to make room for it.
    #
    # byteslice can cut a multi-byte character in half; scrub("") drops the partial
    # bytes rather than emitting invalid UTF-8 into a unique index.
    def truncate(base, suffix:)
      tail = suffix ? "-#{suffix}" : ""
      budget = MAX_BYTES - tail.bytesize
      trimmed = base.byteslice(0, budget).to_s.scrub("")
      "#{trimmed.sub(/-+\z/, "")}#{tail}"
    end

    def taken?(record, candidate)
      scope = Publishing::Post.where(type: record.type, slug: candidate)
      scope = scope.where(parent_id: record.parent_id) if record.class.hierarchical?
      scope = scope.where.not(id: record.id) if record.persisted?
      scope.exists?
    end
  end
end
