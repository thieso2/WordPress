# frozen_string_literal: true

module Styling
  # BR-MIGRATE-208 — a working, dependency-free implementation. It is what the
  # specs run against and a reference for the Rails-backed one.
  class InMemoryGlobalStylesStore < GlobalStylesStore
    def initialize
      super
      @records = {}
      @next_id = 1
    end

    # @param stylesheet [String]
    # @return [Hash, nil]
    def find_for_theme(stylesheet)
      @records[stylesheet]
    end

    # @param stylesheet [String]
    # @return [Hash]
    def create_for_theme(stylesheet)
      return @records[stylesheet] if @records.key?(stylesheet)

      record = {
        'id' => @next_id,
        'content' => GlobalStylesStore.initial_content,
        'title' => GlobalStylesStore::INITIAL_TITLE,
        'name' => "wp-global-styles-#{GlobalStylesStore.urlencode(stylesheet)}"
      }
      @next_id += 1
      @records[stylesheet] = record
    end

    # Test/administration helper: replaces the stored document.
    #
    # @param stylesheet [String]
    # @param content [String]
    # @return [Hash]
    def write(stylesheet, content)
      record = create_for_theme(stylesheet)
      record['content'] = content
      record
    end
  end
end
