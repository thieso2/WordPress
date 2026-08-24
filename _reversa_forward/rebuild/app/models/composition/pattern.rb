# frozen_string_literal: true

module Composition
  # AD-02: legacy post_type = 'wp_block', plus the block-patterns module.
  class Pattern < ApplicationRecord
    self.table_name = "patterns"
    validates :slug, presence: true, uniqueness: true
    validates :title, presence: true
  end
end
