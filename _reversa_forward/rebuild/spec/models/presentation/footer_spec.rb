# frozen_string_literal: true

require "rails_helper"

# `Presentation::Footer` — `wp_footer()` — against the captured tail of the oracle's own
# pages, for the same reason Presentation::Head is compared that way: the goldens ARE the
# specification for the 18 literal screens (screen_modernization_decision.md), so a
# hand-written expectation here would only re-state the author's reading of
# default-filters.php.
RSpec.describe Presentation::Footer do
  PRESENTATION_FOOTER_GOLDEN = Rails.root.join("spec/parity/golden")
  PRESENTATION_FOOTER_SITE = "http://127.0.0.1:3100"

  def golden(name)
    lines = File.read(PRESENTATION_FOOTER_GOLDEN.join("golden-web-#{name}.html")).lines.map(&:chomp)
    from = lines.index { |l| l == '<script type="speculationrules">' }
    lines[from...lines.index("</body>")]
  end

  # The harness maps host+port to `<SITE>` (normalizer.rb:115) and masks the `?ver=`
  # cache-buster as `<TIME>` (normalizer.rb:76) on both sides; doing the same here is what
  # makes the emoji loader's `concatemoji` URL comparable.
  def footer_lines
    @footer_lines ||=
      described_class.new(site_url: PRESENTATION_FOOTER_SITE, theme_slug: "twentytwentyfive")
                     .to_html
                     .gsub(PRESENTATION_FOOTER_SITE, "<SITE>")
                     .gsub(/\bver=\d+\.\d+(\.\d+)?(-\w+)?/, "<TIME>")
                     .lines.map(&:chomp)
  end

  it "prints the speculation rules the oracle prints, byte for byte" do
    expect(footer_lines.first(3)).to eq(golden("index").first(3))
  end

  it "prints the emoji settings and the emoji loader, byte for byte" do
    expected = golden("index")
    from = expected.index('<script id="wp-emoji-settings" type="application/json">')
    actual_from = footer_lines.index('<script id="wp-emoji-settings" type="application/json">')
    expect(footer_lines[actual_from..]).to eq(expected[from..])
  end

  # The three screens differ in what the template rendered, and none of that reaches here:
  # `wp_footer()` prints the same fixed sequence on all of them.
  it "prints the same sequence whatever the screen" do
    %w[index not-found-404 page].each do |name|
      expect(golden(name) - footer_lines).to eq([script_module_line(name)]), name
    end
  end

  # ⚠️ The honest statement of what is missing, named rather than left as screen-diff
  # noise: `wp_print_enqueued_script_modules()` (class-wp-script-modules.php) prints one
  # `<script type="module">` per module a rendered block ENQUEUED. Presentation::Head
  # already prints the import map and the modulepreloads, because those come from the
  # static registry (`Assets.script_modules`); this one cannot, because nothing collects
  # enqueues during the render. There is no `ctx.script_modules` counterpart to
  # `ctx.styles`, so the only way to emit this today would be to hard-code it — which
  # would be right on these three screens by coincidence, not by rule.
  #
  # When the collector lands, this expectation fails, which is the point.
  def script_module_line(name)
    golden(name).find { |l| l.include?("navigation/view-js-module") }
  end

  it "is missing exactly the enqueued script modules, and nothing else" do
    missing = golden("index") - footer_lines
    expect(missing.length).to eq(1)
    expect(missing.first).to include('id="@wordpress/block-library/navigation/view-js-module"')
    expect(footer_lines - golden("index")).to eq([])
  end
end
