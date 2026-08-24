# frozen_string_literal: true

module Routing
  # AD-03: replaces the `_wp_old_slug` / `_wp_old_date` postmeta keys. A slug change on a
  # published record creates a Redirect from the path the record used to occupy.
  #
  # target_domain_model.md AGG-Permalink: "A slug change creates a `Redirect` from the old
  # slug; the legacy did this via `_wp_old_slug` postmeta." The redirect belongs to
  # AGG-Permalink, NOT to AGG-Post -- only Routing knows what path a slug produced, because
  # only Routing knows the permalink structure. That is also what keeps the arrow pointing
  # Routing -> Publishing (target_architecture.md Note 2): Publishing never names Routing.
  #
  # The legacy stored one postmeta row per historical slug and resolved it with a LIKE
  # query at 404 time; here the old PATH is the key, so resolution is an index lookup.
  class Redirect < ApplicationRecord
    self.table_name = "redirects"
    belongs_to :post, class_name: "Publishing::Post", optional: true
    validates :from_path, presence: true, uniqueness: true

    # Records where `post` used to live, given the slug it used to carry. Idempotent: a
    # record renamed back and forth does not accumulate duplicate rows, and a path that
    # now belongs to a different record is repointed rather than duplicated.
    def self.record_slug_change!(post, old_slug, structure: PermalinkStructure.current)
      return nil if old_slug.blank? || post.nil?
      return nil if old_slug.to_s == post.slug.to_s

      from = structure.path_for(post, slug: old_slug)
      # A redirect to the path the record currently occupies would be a loop.
      return nil if from == structure.path_for(post)

      redirect = find_or_initialize_by(from_path: from)
      redirect.post = post
      redirect.recorded_at = Time.current
      redirect.save!
      redirect
    end

    # "Requesting the old path resolves to the record." Trailing- and leading-slash
    # variants of the same path are the same path.
    def self.resolve(path, structure: PermalinkStructure.current)
      find_by(from_path: structure.normalize_path(path))&.post
    end
  end
end
