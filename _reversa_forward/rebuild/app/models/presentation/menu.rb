# frozen_string_literal: true

module Presentation
  # AGG-Menu — 🔑 target_domain_model.md calls this "the clearest single win in the model".
  #
  # The legacy stores the entire menu-item model in nine _menu_item_* postmeta keys
  # (BR-MENU-02) and maintains _menu_item_orphaned tombstones (BR-MENU-05) SOLELY
  # because there are no foreign keys to cascade (F-DD-01). Real columns plus one FK
  # delete both the orphan problem and the machinery that worked around it.
  class Menu < ApplicationRecord
    self.table_name = "menus"
    has_many :menu_items, class_name: "Presentation::MenuItem", dependent: :destroy
    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true

    def roots = menu_items.where(parent_id: nil).order(:position)
  end
end
