# frozen_string_literal: true

module Discussion
  # "A comment is admitted only after a ModerationVerdict; the verdict, not the comment,
  # carries the reason." target_domain_model.md § AGG-Comment.
  class ModerationVerdict < ApplicationRecord
    self.table_name = "moderation_verdicts"
    belongs_to :comment, class_name: "Discussion::Comment"
    # target_data_model.md names the column `decided_by`, not `decided_by_id`, so the
    # foreign key is stated rather than inferred.
    belongs_to :decided_by, class_name: "Identity::User", foreign_key: :decided_by,
                            optional: true, inverse_of: false
    validates :outcome, :reason, presence: true
  end
end
