# frozen_string_literal: true

require "rails_helper"
require_relative "oracle"

# `rake theme:generate` — the theme's documents, checked byte-for-byte against the
# templates WordPress itself builds.
RSpec.describe "theme:generate" do
  let(:rows) { JSON.parse(File.read(Rails.root.join("db/theme/templates.json"))) }

  it "captures the theme's 8 templates and 7 parts" do
    expect(rows.count { |r| r["kind"] == "template" }).to eq(8)
    expect(rows.count { |r| r["kind"] == "part" }).to eq(7)
    expect(rows.select { |r| r["kind"] == "template" }.map { |r| r["slug"] }).to match_array(
      %w[404 archive home index page page-no-title search single]
    )
    expect(rows.select { |r| r["kind"] == "part" }.map { |r| r["slug"] }).to match_array(
      %w[footer footer-columns footer-newsletter header header-large-title sidebar vertical-header]
    )
  end

  # ⚠️ The whole point of storing the BUILT content rather than the file: WordPress runs
  # every theme file through `apply_block_hooks_to_content()`
  # (block-template-utils.php:662), whose default visitor stamps the active stylesheet
  # onto every `core/template-part` block (block-template-utils.php:566). The templates
  # therefore differ from their files by exactly `,"theme":"twentytwentyfive"` per
  # template-part block — and if the generator got the re-serialization wrong anywhere
  # else, this is where it shows.
  it "matches get_block_template() byte for byte, theme attribute injection included" do
    skip "the PHP oracle is not available" unless Presentation::SpecOracle.available?

    oracle = Presentation::SpecOracle.block_templates(rows)
    mismatched = rows.reject { |r| oracle["#{r["kind"]}:#{r["slug"]}"] == r["content"] }
    expect(mismatched.map { |r| "#{r["kind"]}:#{r["slug"]}" }).to eq([])
  end

  it "injects the theme attribute only where the file does not already carry one" do
    home = rows.find { |r| r["slug"] == "home" }
    file = File.read("/workspace/WordPress/wp-content/themes/twentytwentyfive/templates/home.html")
    expect(home["content"].bytesize - file.bytesize).to eq(2 * %(,"theme":"twentytwentyfive").bytesize)
    expect(home["content"]).to include(%(<!-- wp:template-part {"slug":"header","theme":"twentytwentyfive"} /-->))
    # Parts contain no template-part blocks, so nothing is injected into them.
    part = rows.find { |r| r["slug"] == "header" }
    expect(part["content"]).to eq(
      File.read("/workspace/WordPress/wp-content/themes/twentytwentyfive/parts/header.html")
    )
  end

  it "records the area of every part from theme.json, defaulting to uncategorized" do
    areas = rows.select { |r| r["kind"] == "part" }.to_h { |r| [r["slug"], r["area"]] }
    expect(areas).to eq(
      "footer" => "footer", "footer-columns" => "footer", "footer-newsletter" => "footer",
      "header" => "header", "header-large-title" => "header", "vertical-header" => "header",
      "sidebar" => "uncategorized"
    )
  end

  it "captures the theme's 98 patterns with their content already evaluated" do
    patterns = JSON.parse(File.read(Rails.root.join("db/theme/patterns.json")))
    expect(patterns.length).to eq(98)
    # 75 of the 98 pattern FILES contain PHP; if the generator had merely copied the file
    # body, the content would still carry `<?php`.
    expect(patterns.none? { |p| p["content"].include?("<?php") }).to be(true)
    expect(patterns.map { |p| p["slug"] }).to all(start_with("twentytwentyfive/"))
  end

  # The head assets are copies, and a copy that has drifted is worse than no copy.
  it "copies the head stylesheet assets verbatim from the legacy tree" do
    assets = JSON.parse(File.read(Rails.root.join("db/theme/assets.json")))
    {
      "wp-block-library" => "/workspace/WordPress/wp-includes/css/dist/block-library/common.min.css",
      "wp-block-template-skip-link" => "/workspace/WordPress/wp-includes/css/wp-block-template-skip-link.min.css",
      "twentytwentyfive-style" => "/workspace/WordPress/wp-content/themes/twentytwentyfive/style.min.css",
    }.each do |handle, path|
      expect(assets.fetch(handle)["css"]).to eq(File.read(path)), handle
    end
    # The two that are string literals in the legacy source rather than files.
    expect(assets.fetch("wp-img-auto-sizes-contain")["css"])
      .to eq('img:is([sizes=auto i],[sizes^="auto," i]){contain-intrinsic-size:3000px 1500px}')
    expect(assets.fetch("wp-emoji-styles")["css"]).to start_with("\n\timg.wp-smiley, img.emoji {")
  end
end
