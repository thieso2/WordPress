# frozen_string_literal: true

module Discussion
  # AGG-Comment — target_domain_model.md § AGG-Comment.
  #
  # One of the few legacy modules with a real boundary already (blast radius 5, outside
  # the 23-module component). Three deviations, each fixing a defect rather than
  # reproducing it — see BR-CMT-04, BR-CMT-08 and BR-CMT-10 below.
  class Comment < ApplicationRecord
    self.table_name = "comments"

    # wp_allow_comment() gives TWO kinds of answer and the legacy returns them through
    # the same channel. A WP_Error return means the submission NEVER BECAME A COMMENT
    # (409 duplicate, 429 flood, 200 over-length); the 0/1/'spam'/'trash' return is a
    # VERDICT on a comment that did. Here they are separate: a rejection raises and
    # persists nothing, a verdict is recorded against a saved row. Codes, messages and
    # HTTP statuses are the legacy's own, verbatim.
    class Rejected < StandardError
      attr_reader :code, :http_status

      def initialize(code, message, http_status)
        @code = code
        @http_status = http_status
        super(message)
      end
    end

    # BR-MIGRATE-076 (BR-CMT-12): the legacy column is a varchar(20) with values
    # 1, 0, spam, trash, post-trashed and no constraint behind it. Resolved as an ENUM
    # at the Curator pause. T-05 maps the five legacy values onto four states.
    STATUSES = %w[pending approved spam trashed].freeze
    enum :status, STATUSES.index_with(&:itself), validate: true, scopes: false
    STATUSES.each { |s| scope :"in_#{s}", -> { where(status: s) } }

    belongs_to :post, class_name: "Publishing::Post", counter_cache: :comment_count
    belongs_to :parent, class_name: "Discussion::Comment", optional: true
    belongs_to :user, class_name: "Identity::User", optional: true
    has_many :replies, class_name: "Discussion::Comment", foreign_key: :parent_id, dependent: :destroy
    has_many :moderation_verdicts, class_name: "Discussion::ModerationVerdict", dependent: :destroy

    validates :content, presence: true
    validate :thread_depth_within_limit
    validate :parent_belongs_to_same_post

    scope :approved, -> { where(status: :approved) }
    scope :oldest_first, -> { order(:submitted_at, :id) }

    # BR-MIGRATE-071 (BR-CMT-07): a comment containing comment_max_links or more
    # '<a ... href' occurrences is held.
    LINK_PATTERN = /<a\s[^>]*href/i

    def link_count = content.to_s.scan(LINK_PATTERN).length

    # The whole moderation pipeline, as one readable method.
    #
    # ⚠️ BR-MIGRATE-078 (BR-CMT-14): in the legacy the final approval value always
    # passes through the pre_comment_approved filter, "so a plugin can override the
    # entire pipeline's verdict". Under AD-01 there is no filter. The verdict computed
    # here IS the verdict — permanently, with no override mechanism. That is the rule
    # carried forward: the value is final.
    def self.moderate(attributes, actor: nil, settings: Configuration::Setting)
      comment = new(attributes)
      verdict = Discussion::ModerationPolicy.new(comment, actor: actor, settings: settings).call
      comment.status = verdict.outcome
      comment.transaction do
        comment.save!
        comment.moderation_verdicts.create!(outcome: verdict.outcome, reason: verdict.reason,
                                            decided_by: actor)
      end
      comment
    end

    def approve!(by: nil)  = record_verdict!(:approved, "manually approved", by)
    def unapprove!(by: nil) = record_verdict!(:pending, "manually unapproved", by)
    def mark_spam!(by: nil) = record_verdict!(:spam, "manually marked as spam", by)
    def trash!(by: nil)     = record_verdict!(:trashed, "manually trashed", by)

    def depth
      d = 1
      node = parent
      seen = Set.new([id])
      while node && !seen.include?(node.id)
        seen << node.id
        d += 1
        node = node.parent
      end
      d
    end

    private

    def record_verdict!(outcome, reason, actor)
      transaction do
        update!(status: outcome)
        moderation_verdicts.create!(outcome: outcome.to_s, reason: reason, decided_by: actor)
      end
    end

    def thread_depth_within_limit
      max = Configuration::Setting["thread_comments_depth"]
      return if max.blank? || max == false

      errors.add(:parent_id, "exceeds the configured thread depth of #{max}") if depth > max.to_i
    end

    def parent_belongs_to_same_post
      return if parent.nil? || parent.post_id == post_id

      errors.add(:parent_id, "must belong to the same commentable record")
    end
  end
end
