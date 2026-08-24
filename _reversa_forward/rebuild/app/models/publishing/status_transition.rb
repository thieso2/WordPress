# frozen_string_literal: true

module Publishing
  # AD-01: the legacy fired the `transition_post_status` action. This is a row.
  # target_domain_model.md § Domain events: "Where the legacy fired an action on a
  # state change, the target records the transition instead."
  class StatusTransition < ApplicationRecord
    self.table_name = "post_status_transitions"
    belongs_to :post, class_name: "Publishing::Post"
    belongs_to :actor, class_name: "Identity::User", optional: true
    scope :newest_first, -> { order(occurred_at: :desc) }
  end
end
