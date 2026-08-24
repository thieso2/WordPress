# frozen_string_literal: true

module Identity
  class ApplicationPassword < ApplicationRecord
    self.table_name = "application_passwords"
    belongs_to :user, class_name: "Identity::User"
    validates :name, :digest, presence: true
  end
end
