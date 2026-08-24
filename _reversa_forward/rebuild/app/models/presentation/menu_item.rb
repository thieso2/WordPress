# frozen_string_literal: true

module Presentation
  # T-04 pivots the nine _menu_item_* postmeta keys into these columns.
  #
  # The menu_items_one_target CHECK is the invariant the legacy could not express:
  # "An item targets exactly one of: a content record, a term, a custom URL. Not zero,
  # not two." _menu_item_type decides which arm applies.
  class MenuItem < ApplicationRecord
    self.table_name = "menu_items"

    belongs_to :menu, class_name: "Presentation::Menu"
    belongs_to :parent, class_name: "Presentation::MenuItem", optional: true
    has_many :children, class_name: "Presentation::MenuItem", foreign_key: :parent_id,
                        dependent: :destroy
    belongs_to :target, polymorphic: true, optional: true

    validate :exactly_one_target
    validate :parent_is_in_the_same_menu

    private

    # Mirrors the CHECK constraint so the failure is a validation error rather than a
    # PG::CheckViolation. Both are kept: the constraint is the guarantee, the validation
    # is the message.
    def exactly_one_target
      internal = target_type.present? && target_id.present?
      custom = url.present?
      return if internal ^ custom

      errors.add(:base, "an item targets exactly one of: an internal record, or a custom URL")
    end

    def parent_is_in_the_same_menu
      return if parent.nil? || parent.menu_id == menu_id

      errors.add(:parent_id, "must belong to the same menu")
    end
  end
end
