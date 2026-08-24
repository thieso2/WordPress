# frozen_string_literal: true

module Classification
  # Promoted from term_taxonomy.taxonomy, a string column, to a record.
  class Taxonomy < ApplicationRecord
    self.table_name = "taxonomies"
    has_many :terms, class_name: "Classification::Term", dependent: :destroy
    validates :name, presence: true, uniqueness: true
  end
end
