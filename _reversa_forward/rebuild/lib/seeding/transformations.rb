# frozen_string_literal: true

require "bcrypt"

module Seeding
  # T-01 … T-11, one method each, named for the transformation they implement so a
  # reader can check them against data_migration_plan.md § Transformations line by line.
  module Transformations
    ZERO_DATE = "0000-00-00 00:00:00"

    module_function

    # ── T-01: Zero dates → NULL ──────────────────────────────────────────────────
    # "The GMT column is the source of truth and becomes the single timestamptz
    #  (AD-07); the local column is DISCARDED, since it is derivable from the site
    #  timezone." Any OTHER unparseable datetime is rejected, never coerced.
    def zero_date_to_null(value)
      return nil if value.nil?

      s = value.to_s.strip
      return nil if s.empty? || s.start_with?("0000-00-00")

      # The oracle's datetimes are naive UTC in the *_gmt columns.
      Time.find_zone("UTC").parse(s) or raise ArgumentError, "unparseable datetime #{s.inspect}"
    rescue ArgumentError, TypeError
      raise ArgumentError, "unparseable datetime #{value.inspect}"
    end

    # ── T-05: comment_approved varchar → enum ────────────────────────────────────
    COMMENT_STATUS = {
      "1" => "approved", "0" => "pending", "spam" => "spam",
      "trash" => "trashed", "post-trashed" => "trashed"
    }.freeze

    def comment_status(raw)
      COMMENT_STATUS.fetch(raw.to_s) do
        raise ArgumentError, "unmapped comment_approved value #{raw.inspect}"
      end
    end

    # ── post_status varchar → enum ───────────────────────────────────────────────
    POST_STATUS = {
      "publish" => "published", "draft" => "draft", "pending" => "pending",
      "private" => "private", "future" => "scheduled", "trash" => "trashed",
      "auto-draft" => "auto_draft"
    }.freeze

    def post_status(raw)
      POST_STATUS.fetch(raw.to_s) { raise ArgumentError, "unmapped post_status #{raw.inspect}" }
    end

    # ── BR-MIGRATE-032: slugs are not allocated for draft / pending / auto_draft ──
    # The legacy writes post_name = ''. NULL here, which is load-bearing: reproducing
    # NOT NULL DEFAULT '' would collide every draft against every other in the unique
    # index (handoff.md, "Six things", item 1).
    def slug_or_null(raw)
      s = raw.to_s
      s.empty? ? nil : s
    end

    # ── T-07: guid → UUID ────────────────────────────────────────────────────────
    # "DISCARD the legacy value; generate a fresh UUID." The legacy guid is a permalink
    # captured at first publish and never updated (BR-POST-10) — a stale URL, not an
    # identifier. ⚠️ Expected oracle diff: feeds expose guid, so feed output differs by
    # design and the harness must normalize it.
    def fresh_guid = SecureRandom.uuid

    # ── T-08: Slashing — no transformation, by definition ────────────────────────
    # "The pipeline copies bytes." Recorded as a method so that its absence is visible:
    # adding an unslash pass here would corrupt every legitimate backslash in the corpus.
    def text(raw) = raw.nil? ? "" : raw.to_s

    # ── T-10: Password hashes ────────────────────────────────────────────────────
    # "COPY THE DIGEST VERBATIM. Do not rehash — the plaintext is unavailable by
    #  construction." An empty or malformed digest loads the user with authentication
    #  disabled; never leave a digest that accidentally verifies.
    DISABLED_DIGEST = "*disabled*"

    # Format recognition lives in Identity::LegacyDigest so the pipeline and the
    # authentication path cannot disagree about what a valid digest is — which is
    # exactly how "load the user with authentication disabled" silently became true for
    # every user in the corpus on the first run.
    def password_digest(raw)
      s = raw.to_s
      return DISABLED_DIGEST if s.empty?

      Identity::LegacyDigest.recognised?(s) ? s : DISABLED_DIGEST
    end

    def authentication_disabled?(digest) = digest == DISABLED_DIGEST

    # ── Not in the plan: post_password ───────────────────────────────────────────
    # ⚠️ target_data_model.md renames the legacy's PLAINTEXT `post_password` column to
    # `password_digest`, but data_migration_plan.md § Transformations specifies no
    # transformation for it. The rename cannot be honoured by copying: a plaintext value
    # in a column named `_digest` is worse than either option alone. Hashed here, and
    # reported. Consequence: the plaintext is not recoverable, which is the point.
    def post_password_digest(raw)
      s = raw.to_s
      s.empty? ? nil : BCrypt::Password.create(s)
    end

    # ── T-03: the serialized role map → rows ─────────────────────────────────────
    # Under multisite the meta_key prefix encodes the site (wp_capabilities,
    # wp_3_capabilities, …), so the site id is parsed out of the key (F-MS-04).
    CAPABILITIES_KEY = /\A(?<prefix>.+?)(?:(?<site>\d+)_)?capabilities\z/

    def site_id_from_capabilities_key(meta_key, table_prefix)
      return nil unless meta_key.start_with?(table_prefix)

      rest = meta_key.delete_prefix(table_prefix)
      m = rest.match(/\A(?:(\d+)_)?capabilities\z/)
      return nil if m.nil?

      m[1]&.to_i
    end
  end
end
