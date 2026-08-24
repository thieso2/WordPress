# frozen_string_literal: true

module Syndication
  # The oEmbed cache was a POST TYPE in the legacy (post_type = 'oembed_cache').
  # It is a cache. AD-02.
  #
  # ⚠️ The TTL is RE-DERIVED by the pipeline, not migrated: a cache's expiry has no
  # meaning once it has been moved.
  class EmbedCache < ApplicationRecord
    self.table_name = "embed_caches"
    validates :url_digest, presence: true, uniqueness: true
    scope :live, -> { where(expires_at: Time.current..) }

    def self.digest_for(url) = Digest::SHA256.hexdigest(url.to_s)
  end
end
