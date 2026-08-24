# frozen_string_literal: true

module Publishing
  # AD-03: the RESIDUAL bucket only. Every core-owned postmeta key became a column,
  # an association or a table; what remains is genuinely arbitrary user metadata.
  #
  # AD-05: the (post_id, key) unique index replaces add_metadata()'s
  # SELECT COUNT(*) then INSERT with nothing behind it (F-META-02). The legacy's
  # uniqueness guarantee was advisory; here it is the database's.
  #
  # ⚠️ Two storage shapes, one bucket. A key that holds ONE value is a row here, and
  # the unique index is what makes that a guarantee. A key that holds SEVERAL values
  # cannot satisfy that index, so it lives in `posts.residual_attributes` as a jsonb
  # array — where array order carries BR-MIGRATE-028's insertion order (the legacy
  # got it from `ORDER BY meta_id ASC`, which is a property of an autoincrement, not
  # a promise). `public_payload` below reads both, because "the record's attributes"
  # to anything outside Publishing means both.
  #
  # AD-01: no filters. `is_protected_meta` is a filtered predicate in the legacy
  # (`apply_filters( 'is_protected_meta', ... )`, meta.php:1326); here the unfiltered
  # default is the permanent, only answer.
  class Attribute < ApplicationRecord
    self.table_name = "post_attributes"

    # BR-MIGRATE-022 (legacy BR-META-04, wp-includes/meta.php:1312): a key is
    # protected when the key, stripped of every character that is not printable
    # ASCII or a Unicode letter, begins with an underscore.
    #
    # ⚠️ The rule is stated in CHARACTERS and implemented here in characters. The
    # legacy's `preg_replace( "/[^\x20-\x7E\p{L}]/", '', $meta_key )` carries no /u
    # modifier, so PCRE walks it BYTE by byte: for "é_foo" it keeps the 0xC3 lead byte
    # (a Latin letter on its own) and drops the 0xA9 continuation, yielding a broken
    # string that no longer starts with '_' — so the legacy reports a key like
    # "é_foo" as UNPROTECTED. Verified against the oracle. Reproducing that would be
    # reproducing a mojibake bug, not a rule; see the divergence note in the parity
    # report.
    NON_KEY_CHARACTERS = /[^\x20-\x7E\p{L}]/

    # The same predicate, expressed for the query planner rather than for Ruby, so a
    # public read never has to load a protected row in order to discard it.
    # ' ' .. '~' is printable ASCII; [:alpha:] is the Unicode letter class under a
    # UTF-8 database.
    SQL_SANITIZED_KEY = "regexp_replace(key, '[^ -~[:alpha:]]', '', 'g')"

    belongs_to :post, class_name: "Publishing::Post"

    validates :key, presence: true, uniqueness: { scope: :post_id }
    # jsonb NOT NULL: `false` and `[]` are values, `nil` is not one. `presence` would
    # reject the first two.
    validates :value, exclusion: { in: [nil] }

    scope :with_key, ->(key) { where(key: key) }

    # TD-07 / F-DD-02: `meta_value` is unindexed in all six legacy meta tables, which
    # is what makes `meta_query` the dominant slow-query source. Filtering by value is
    # a first-class read here rather than something callers assemble by hand.
    scope :with_value, ->(key, value) { where(key: key, value: value) }

    scope :exposed,   -> { where("left(#{SQL_SANITIZED_KEY}, 1) IS DISTINCT FROM '_'") }
    scope :protected_, -> { where("left(#{SQL_SANITIZED_KEY}, 1) = '_'") }

    def self.protected_key?(key)
      key.to_s.gsub(NON_KEY_CHARACTERS, "").start_with?("_")
    end

    def protected? = self.class.protected_key?(key)

    # The records carrying `key` = `value`. Returns posts, not attribute rows: the
    # caller asked which records match, and `Attribute` is an entity of AGG-Post, not
    # a thing anyone outside the aggregate holds.
    def self.records_with(key:, value:)
      Publishing::Post.where(id: with_value(key, value).select(:post_id))
    end

    # What a public read of the record's attributes returns: both storage shapes,
    # protected keys removed. BR-MIGRATE-022 — the legacy reaches the same outcome by
    # never registering a protected key for REST exposure, so an unregistered or
    # protected key is ABSENT from the response rather than present-and-null
    # (confirmed against the oracle: GET /wp/v2/posts/:id returns no entry at all).
    def self.public_payload(post)
      multi = post.residual_attributes.reject { |k, _| protected_key?(k) }
      single = where(post_id: post.id).exposed.order(:key).to_h { |row| [row.key, row.value] }
      multi.merge(single)
    end
  end
end
