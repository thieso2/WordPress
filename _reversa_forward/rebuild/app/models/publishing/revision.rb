# frozen_string_literal: true

module Publishing
  # AD-02: split out of wp_posts. A revision is an audit record, not content —
  # which is why the legacy has to exclude post_type='revision' from nearly every query.
  #
  # Two kinds share the table, as they shared `post_type = 'revision'` in the legacy:
  # a REVISION (`{id}-revision-v1`) is a copy of the record as it stood after an update,
  # and an AUTOSAVE (`{id}-autosave-v1`) is an editor's unsaved draft of it, one per
  # author, overwritten in place (wp-admin/includes/post.php:1975). The `autosave` flag
  # replaces the legacy's string-prefix test on post_name (revision.php:176).
  class Revision < ApplicationRecord
    self.table_name = "revisions"
    belongs_to :post, class_name: "Publishing::Post"
    belongs_to :author, class_name: "Identity::User", optional: true

    # `_wp_post_revision_fields()` (revision.php:22): title, content, excerpt. AD-01: the
    # `_wp_post_revision_fields` filter that could extend the list is gone.
    FIELDS = %w[title content excerpt].freeze

    # wp_get_post_revisions() orders by post_date DESC, ID DESC (revision.php:690). The
    # id tiebreak is load-bearing: two revisions written inside one frozen-clock second
    # carry the same created_at, and "the latest revision" must still mean the last one.
    scope :newest_first, -> { order(created_at: :desc, id: :desc) }
    scope :oldest_first, -> { order(created_at: :asc, id: :asc) }
    scope :autosaves, -> { where(autosave: true) }
    scope :regular, -> { where(autosave: false) }

    # normalize_whitespace(), wp-includes/formatting.php:5590 — the comparison the legacy
    # applies to every revisioned field before deciding whether anything changed
    # (revision.php:190). Trailing whitespace, CRLF vs LF and runs of spaces are not
    # changes; verified against the oracle, which records no revision for "v2" -> "v2  \n".
    #
    # PHP's trim() strips " \t\n\r\0\x0B" and nothing else; Ruby's String#strip would
    # also strip form feed, and the oracle records a revision for "\fx" -> "x" where the
    # port would not. Verified byte-for-byte (commands_differential_spec, normalize_whitespace).
    PHP_TRIM = /\A[ \t\n\r\0\v]+|[ \t\n\r\0\v]+\z/

    def self.normalize_whitespace(value)
      value.to_s.gsub(PHP_TRIM, "").tr("\r", "\n").gsub(/\n+/, "\n").gsub(/[ \t]+/, " ")
    end

    # Whether `candidate` (anything answering title/content/excerpt, or a Hash of them)
    # differs from this revision in any revisioned field, under normalize_whitespace.
    def differs_from?(candidate)
      FIELDS.any? do |field|
        theirs = candidate.is_a?(Hash) ? candidate[field] || candidate[field.to_sym] : candidate.public_send(field)
        self.class.normalize_whitespace(theirs) != self.class.normalize_whitespace(public_send(field))
      end
    end
  end
end
