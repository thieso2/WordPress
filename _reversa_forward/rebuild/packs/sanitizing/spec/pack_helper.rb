# frozen_string_literal: true

# The `sanitizing` pack is pure Ruby: no Rails, no ActiveSupport, no other pack.
# Zeitwerk autoloads these files in the application; the specs load them directly
# so that `bundle exec rspec packs/sanitizing/spec` proves the pack really does
# stand on the stdlib alone.
%w[
  bytes
  tables
  accents
  html_decoder
  attribute_parser
  css
  kses
  formatting
  texturize
  options
  safe_html
].each { |file| require_relative "../app/sanitizing/#{file}" }
