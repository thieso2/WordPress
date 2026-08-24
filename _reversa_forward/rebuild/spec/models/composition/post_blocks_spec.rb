# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"

# The properties of the post + site family that the SCREEN DIFF CANNOT SEE, plus the two
# places where the block output has to be checked against the golden files rather than
# against a CLI `render_block()`.
#
# spec/parity/harness/normalizer.rb sorts class-attribute tokens, and says so in a warning:
# "⚠️ Note this normalization hides BR-MIGRATE-201 (first writer takes the slot, later ones
# append). That rule must therefore be asserted by a unit test … the screen diff can no
# longer see it." This file is where that debt is paid for this family.
RSpec.describe Composition::Renderers::PostBlocks do
  let(:author) do
    Identity::User.new(login: "oracle_admin", nicename: "oracle_admin",
                       email: "oracle@example.com", display_name: "oracle_admin")
               .tap { |u| u.password_digest = "$2a$12$#{"x" * 53}"; u.save!(validate: false) }
  end

  let(:post) do
    Publishing::Article.create!(title: "Hello world!", slug: "hello-world", author: author,
                                content: "<!-- wp:paragraph -->\n<p>Body</p>\n<!-- /wp:paragraph -->",
                                excerpt: "", status: "published",
                                published_at: Time.utc(2026, 3, 15, 9, 59))
  end

  # ⚠️ Inside the example's transaction, so it is rolled back and cannot damage a
  # concurrent run. It exists because other spec files in this directory seed corpora
  # from `before(:all)`, which `use_transactional_fixtures` does NOT roll back — their
  # rows outlive their file and collide with these fixtures' natural keys.
  def purge!
    %w[comments term_assignments terms taxonomies asset_variants assets posts users
       settings].each { |table| ActiveRecord::Base.connection.execute("DELETE FROM #{table}") }
  end

  before do
    purge!
    Configuration::Setting.set("blogname", "Reversa Oracle &quot;7.2&quot; 😀")
    Configuration::Setting.set("blogdescription", "A tagline")
    Configuration::Setting.set("siteurl", "http://127.0.0.1:8099")
    Configuration::Setting.set("home", "http://127.0.0.1:8099")
    Configuration::Setting.set("date_format", "F j, Y")
    Configuration::Setting.set("timezone_string", "Europe/Madrid")
  end

  def render(markup, ctx = Composition::RenderContext.new(post: post))
    Composition::Renderer.render(Composition::Parser.parse(markup), ctx)
  end

  describe "get_block_wrapper_attributes (class-wp-block-supports.php:203)" do
    # The merge table is `style`, `class`, `id`, `aria-label`, in that order, and PHP
    # array order is what reaches the output.
    it "emits style before class" do
      html = render('<!-- wp:post-terms {"term":"category","style":{"typography":{"fontWeight":"300"}}} /-->',
                    wrapped_context)
      expect(html).to start_with('<div style="font-weight:300" class="')
    end

    # BR-MIGRATE-201, and the half the normalizer erases: the callback's OWN classes come
    # first, the supports' after, and duplicates collapse.
    it "puts the callback's extra classes ahead of the supports' own" do
      html = render('<!-- wp:post-terms {"term":"category"} /-->', wrapped_context)
      expect(html).to include('class="taxonomy-category wp-block-post-terms"')
    end

    it "orders align, custom-classname and generated-classname by wp-settings.php load order" do
      html = render('<!-- wp:post-content {"align":"full","className":"mine","layout":{"type":"constrained"}} /-->')
      # `align` is registered at wp-settings.php:415 and `custom-classname` at :417, so
      # `alignfull` precedes `mine`; `entry-content` is the callback's own extra and leads.
      expect(html).to include('class="entry-content alignfull mine wp-block-post-content ' \
                              'has-global-padding is-layout-constrained wp-block-post-content-is-layout-constrained"')
    end

    it "returns an empty attribute string when nothing contributes" do
      expect(Composition::Renderers::PostBlocks::Supports.wrapper_attributes("core/nope", {})).to eq("")
    end
  end

  describe "core/post-content recursion (post-content.php:19)" do
    # The legacy guards with a function-static `$seen_ids`; the port carries the set down
    # the child RenderContext instead (paradigm_decision.md implication 1).
    it "renders nothing for a post whose content embeds itself" do
      post.update_column(:content, "<!-- wp:post-content /-->")
      expect(render("<!-- wp:post-content /-->")).to eq("")
    end

    it "still renders the same post twice when the two are siblings, not nested" do
      html = render("<!-- wp:post-content /--><!-- wp:post-content /-->")
      expect(html.scan("entry-content").length).to eq(2)
    end
  end

  describe "the golden screens" do
    GOLDEN = Rails.root.join("spec/parity/golden")

    def golden(name) = File.read(GOLDEN.join("golden-web-#{name}.html"))

    it "produces the post title the single screen shows" do
      expect(golden("single")).to include('<h1 class="wp-block-post-title">Hello world!</h1>')
      expect(render('<!-- wp:post-title {"level":1} /-->'))
        .to eq('<h1 class="wp-block-post-title">Hello world!</h1>')
    end

    # ⚠️ `loading` / `fetchpriority` / the `auto, ` sizes prefix come from
    # `wp_increase_content_media_count()`, a page-scoped PHP function-static. A CLI
    # render_block() says `loading="lazy"`; the PAGE says `fetchpriority="high"`. The
    # golden files are the target, so this is where that half is pinned.
    it "matches the golden files' featured-image loading attributes, not the CLI's" do
      goldens = Dir[GOLDEN.join("golden-web-*.html")].map { |f| File.read(f) }
      with_featured = goldens.select { |g| g.include?("wp-post-image") }
      expect(with_featured).not_to be_empty
      expect(with_featured.all? { |g| g.include?('fetchpriority="high"') }).to be(true)
      expect(goldens.none? { |g| g.include?('loading="lazy"') }).to be(true)
      expect(goldens.none? { |g| g.include?("sizes=\"auto, ") }).to be(true)

      # ⚠️ The four expectations above describe the GOLDEN FILES only — they hold whatever
      # the renderer does. The rendered block has to be asserted too, or the CLI's
      # `loading="lazy"` could come back unnoticed: post_blocks_differential_spec.rb
      # normalizes exactly these three tokens away on both sides, so this is the only
      # place in the family that pins them.
      asset = Library::Asset.create!(title: "img", slug: "img", mime_type: "image/png",
                                     byte_size: 1, width: 1600, height: 1200,
                                     metadata: { "file" => "2026/08/oracle-image.png" })
      asset.variants.create!(size_name: "medium", width: 300, height: 225, mime_type: "image/png")
      post.update!(featured_asset: asset)

      html = render("<!-- wp:post-featured-image /-->")
      expect(html).to include("wp-post-image")
      expect(html).to include('fetchpriority="high"')
      expect(html).not_to include('loading="lazy"')
      expect(html).to include('sizes="(max-width: 1600px) 100vw, 1600px"')
      expect(html).not_to include('sizes="auto, ')
    end

    it "matches the golden files' avatar attributes" do
      comments = golden("comments")
      expect(comments).to include("class='avatar avatar-50 photo wp-block-avatar__image' " \
                                  "height='50' width='50' decoding='async'/>")
    end
  end

  # ── core/site-logo, the branch the corpus could not reach ───────────────────────
  #
  # The oracle corpus sets no `site_logo` option, so every case in
  # post_blocks_differential_spec.rb takes `get_custom_logo()`'s EMPTY path and returns
  # ''. The whole non-empty half of site-logo.php was therefore unverified, and it hid
  # two behaviours that were missing from the port:
  #
  #   * site-logo.php:18-30 — the callback installs its OWN `wp_get_attachment_image_src`
  #     closure around `get_custom_logo()` to rescale the image to `attributes.width`.
  #     Core's own closure, added and removed by the callback itself, so it is behaviour
  #     and not an extension point (AD-01).
  #   * site-logo.php:41-51 — `linkTarget: "_blank"` adds `aria-label` and `target` to the
  #     `rel="home"` anchor, via WP_HTML_Tag_Processor.
  #
  # DIFFERENTIAL: `support/site_logo_oracle.php` supplies both the fixture and the
  # expectation, with a `pre_option_site_logo` filter that lives in the PHP process only —
  # the shared oracle database is never written to. One process PER CASE, because
  # `wp_increase_content_media_count()` is a page-scoped static and would otherwise
  # suppress `fetchpriority` on every case after the first.
  # ⚠️ Namespaced deliberately: a constant assigned inside an RSpec.describe block lands
  # on Object, and packs/styling/spec/differential_spec.rb already owns the name
  # ORACLE_BOOTSTRAP.
  module SiteLogoOracle
    BRIDGE = File.expand_path("support/site_logo_oracle.php", __dir__)
    BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"

    MARKUPS = [
      "<!-- wp:site-logo /-->",
      '<!-- wp:site-logo {"width":120} /-->',
      '<!-- wp:site-logo {"isLink":false} /-->',
      '<!-- wp:site-logo {"linkTarget":"_blank"} /-->',
      '<!-- wp:site-logo {"width":60,"linkTarget":"_blank"} /-->',
      '<!-- wp:site-logo {"width":0} /-->',
      '<!-- wp:site-logo {"isLink":false,"linkTarget":"_blank"} /-->'
    ].freeze
  end

  describe "core/site-logo against the PHP oracle" do
    def oracle(markup)
      stdout, stderr, status = Open3.capture3(
        { "WP_ORACLE_BOOTSTRAP" => SiteLogoOracle::BOOTSTRAP }, "php", SiteLogoOracle::BRIDGE,
        stdin_data: JSON.generate([markup])
      )
      raise "site-logo bridge failed: #{stderr}" unless status.success?

      JSON.parse(stdout)
    end

    # Projects the oracle's own attachment onto the target schema, exactly as
    # lib/seeding/pipeline.rb does — except that `metadata['sizes']` is KEPT, which is
    # what lets the srcset carry the corpus's real `med-` / `large-` filenames.
    def install(payload)
      payload.fetch("settings").each { |name, value| Configuration::Setting.set(name, value) }
      a = payload.fetch("asset")
      asset = Library::Asset.create!(
        title: a["title"], slug: a["slug"], alt_text: a["alt_text"], mime_type: a["mime_type"],
        byte_size: 1, width: a["width"], height: a["height"], metadata: a["metadata"]
      )
      (a.dig("metadata", "sizes") || {}).each do |name, dims|
        asset.variants.create!(size_name: name, width: dims["width"], height: dims["height"],
                               mime_type: dims["mime-type"].presence || a["mime_type"])
      end
      Configuration::Setting.set("site_logo", asset.id.to_s)
    end

    it "renders every site-logo case byte-identically to render_block()" do
      skip "PHP oracle not available" unless File.exist?(SiteLogoOracle::BOOTSTRAP) &&
                                            system("sh", "-c", "command -v php > /dev/null 2>&1")

      diverged = SiteLogoOracle::MARKUPS.filter_map do |markup|
        payload = oracle(markup)
        purge!
        install(payload)
        want = payload.fetch("rendered").first
        got = render(markup, Composition::RenderContext.new)
        next if got == want

        "#{markup}\n    want: #{want.inspect}\n    got:  #{got.inspect}"
      end

      expect(diverged).to eq([]), -> { "#{diverged.length}/#{SiteLogoOracle::MARKUPS.length} diverged:\n  #{diverged.join("\n  ")}" }
    end

    # The empty branch stays empty — site-logo.php:33, "avoiding extraneous wrapper div".
    it "renders nothing when no logo is set" do
      Configuration::Setting.set("site_logo", "")
      expect(render("<!-- wp:site-logo /-->", Composition::RenderContext.new)).to eq("")
    end
  end

  describe "the recorded divergence, and the srcset that is no longer one" do
    # AD-07 + data_migration_plan.md T-01: ONE timestamptz, local wall clock derived from
    # `timezone_string`. The oracle's corpus has post_date == post_date_gmt with
    # gmt_offset +2, so its own local column disagrees with its own GMT column.
    it "renders the datetime as the stored UTC instant in the site zone" do
      html = render("<!-- wp:post-date /-->")
      expect(html).to include('datetime="2026-03-15T10:59:00+01:00"')
      # The harness normalizes this attribute to <TIME>, so no golden byte moves.
      expect(File.read(Rails.root.join("spec/parity/golden/golden-web-single.html")))
        .to include('<time datetime="<TIME>">')
    end

    # `asset_variants` carries no filename column, so the name rides in
    # `assets.metadata['sizes'][<name>]['file']` — which is what the goldens need, since
    # this corpus renamed its sizes to `med-…` / `large-…`. 10 of the 18 golden screens
    # carry that srcset.
    it "takes srcset candidate filenames from the asset metadata" do
      asset = Library::Asset.create!(
        title: "img", slug: "img", mime_type: "image/png", byte_size: 1,
        width: 1600, height: 1200,
        metadata: { "file" => "2026/08/oracle-image.png",
                    "sizes" => { "medium" => { "file" => "med-oracle-image.png",
                                               "width" => 300, "height" => 225 } } }
      )
      asset.variants.create!(size_name: "medium", width: 300, height: 225, mime_type: "image/png")
      post.update!(featured_asset: asset)

      expect(render("<!-- wp:post-featured-image /-->")).to include("med-oracle-image.png 300w")
      expect(File.read(Rails.root.join("spec/parity/golden/golden-web-home.html")))
        .to include("med-oracle-image.png 300w")
    end

    # The fallback, for an asset whose metadata carries no `sizes` entry: WordPress's own
    # `<base>-<w>x<h>.<ext>`, which is what it would have named the file.
    it "falls back to canonical naming when the metadata carries no sizes entry" do
      asset = Library::Asset.create!(title: "img", slug: "img", mime_type: "image/png",
                                     byte_size: 1, width: 1600, height: 1200,
                                     metadata: { "file" => "2026/08/oracle-image.png" })
      asset.variants.create!(size_name: "medium", width: 300, height: 225, mime_type: "image/png")
      post.update!(featured_asset: asset)

      expect(render("<!-- wp:post-featured-image /-->")).to include("oracle-image-300x225.png 300w")
    end
  end

  private

  def wrapped_context
    taxonomy = Classification::Taxonomy.create!(name: "category", hierarchical: true, object_types: ["post"])
    term = Classification::Term.create!(taxonomy: taxonomy, name: "Uncategorized", slug: "uncategorized")
    Classification::Assignment.create!(term: term, classifiable: post)
    Composition::RenderContext.new(post: post)
  end
end
