# frozen_string_literal: true

module Composition
  # The block-name -> renderer map.
  module Renderers
    def self.registry = @registry ||= {}

    def self.register(block_name, klass) = registry[block_name] = klass

    def self.for(block_name) = registry[block_name.to_s]

    def self.reset! = @registry = {}
  end
end
