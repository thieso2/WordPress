# frozen_string_literal: true

module Composition
  # BR-MIGRATE-200 (BR-BSUP-01): "Supports apply only to blocks with a REGISTERED BLOCK
  # TYPE; unregistered blocks receive nothing." So registration is not bookkeeping — it is
  # the gate that decides whether a block gets styling at all.
  #
  # AD-01: there is no `register_block_type` hook and no runtime registration. The set is
  # fixed at boot from generated data, which is what makes the rendered output final.
  class Registry
    DATA = Rails.root.join("db", "blocks")

    class << self
      def types
        @types ||= JSON.parse(File.read(DATA.join("types.json")))
                       .transform_values { |schema| BlockType.new(schema) }
      end

      def styles
        @styles ||= JSON.parse(File.read(DATA.join("styles.json")))
      end

      def [](name) = types[name.to_s]
      def registered?(name) = types.key?(name.to_s)
      def dynamic = types.values.select(&:dynamic?)
      def reset! = (@types = nil; @styles = nil)

      # The per-block CSS the legacy prints inline as
      # `<style id="wp-block-<name>-inline-css">`. It is an ASSET, shipped beside each
      # block in the legacy tree — not something to reimplement.
      def style_for(name) = styles[name.to_s]
    end
  end
end
