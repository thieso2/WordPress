# frozen_string_literal: true

# topology_decision.md option 3: the `styling` pack is a leaf with zero declared
# dependencies. These specs therefore load it from plain $LOAD_PATH and never
# boot Rails — if a `require "rails"` ever creeps into the pack, this file stops
# working and the specs fail.
STYLING_APP_PATH = File.expand_path('../app', __dir__)
$LOAD_PATH.unshift(STYLING_APP_PATH) unless $LOAD_PATH.include?(STYLING_APP_PATH)

%w[
  php_compat
  css_safety
  css_declarations
  css_rule
  css_rules_store
  css_rules_store_registry
  processor
  block_style_definitions
  style_engine
  block_type
  block_type_registry
  block_supports
  theme_json_schema
  fluid_typography
  theme_json
  core_theme_data
  layout_definitions
  selectors
  blocks_metadata
  stylesheet
  global_stylesheet
  global_styles_store
  in_memory_global_styles_store
  theme_json_resolver
].each { |file| require "styling/#{file}" }
