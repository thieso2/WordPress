# frozen_string_literal: true

require "rails_helper"

# Presentation::Head against the captured `<head>` of the oracle's own pages.
#
# The golden files ARE the specification for this class (screen_modernization_decision.md
# keeps the 18 `web.*` screens literal), so the comparison is made against them directly
# rather than against a paraphrase of them. ~39% of each screen's bytes are the `<style>`
# elements assembled here.
RSpec.describe Presentation::Head do
  PRESENTATION_HEAD_GOLDEN = Rails.root.join("spec/parity/golden")
  PRESENTATION_HEAD_SITE = "http://127.0.0.1:3100"

  # The harness maps host+port to `<SITE>` on both sides (normalizer.rb:115); doing the
  # same here is what makes an absolute self-link comparable.
  def normalize(html) = html.gsub(PRESENTATION_HEAD_SITE, "<SITE>")

  def golden(name) = File.read(PRESENTATION_HEAD_GOLDEN.join("golden-web-#{name}.html")).lines.map(&:chomp)

  # Drops whole `<style id="X-inline-css"> … </style>` elements from a golden's lines.
  def without_styles(lines, handles)
    dropping = false
    lines.reject do |line|
      if handles.any? { |h| line == %(<style id="#{h}-inline-css">) }
        dropping = true
      elsif dropping && line == "</style>"
        dropping = false
        next true
      end
      dropping
    end
  end

  # The block stylesheets are a Composition concern; what this class owns is everything
  # AROUND them. Feeding it the golden's own first-use order isolates the two.
  #
  # ⚠️ BOTH forms are read, and that is the point of the second example group below: a
  # block style appears in a golden either as `<style id="wp-block-X-inline-css">` or as
  # `<link rel='stylesheet' id='wp-block-X-css'>`, and which one is not a property of the
  # block — it is decided per screen by `wp_maybe_inline_styles()`'s 40,000-byte budget.
  # Grepping only the first form would silently drop `navigation` from the queue on the
  # four screens where it is external, and the comparison would then pass while the head
  # was missing a stylesheet.
  def collector_for(lines)
    collector = Composition::StyleCollector.new
    lines.each do |line|
      m = line.match(/\A<style id="wp-block-(.+)-inline-css">\z/) ||
          line.match(/\A<link rel='stylesheet' id='wp-block-(.+)-css'/)
      next unless m

      name = "core/#{m[1]}"
      collector.use(name) if Composition::Registry.style_for(name)
    end
    collector
  end

  # The oracle's own option values, which are already HTML-escaped at rest
  # (BR-MIGRATE-014 / Configuration::Setting::SANITIZED_ON_WRITE) — that is what makes
  # `&quot;` survive as `&quot;` in the title rather than becoming `&amp;quot;`.
  #
  # ⚠️ Written in NAME ORDER. Several suites run against one `rebuild_test` concurrently
  # this wave, and two transactions updating the same `settings` rows in different orders
  # deadlock where two using the same order merely queue.
  PRESENTATION_HEAD_OPTIONS = {
    "blogdescription" => "He said &quot;it&#039;s a test&quot; -- she replied " \
                         "&#039;&quot;nested&quot;&#039; ... 5&#039;9&quot; tall, " \
                         "3&quot; wide « French » 「日本語」 ‘curly’ “already curly”",
    "blogname" => 'Reversa Oracle &quot;7.2&quot; 😀',
    "show_on_front" => "posts",
  }.freeze

  # The Customizer's Additional CSS — the oracle corpus's `custom_css` post named
  # `twentytwentyfive` (oracle tools/seed.php, machinery types), which
  # `wp_enqueue_global_styles()` (script-loader.php:2626) appends to
  # `global-styles-inline-css` on a block theme. The pipeline pivots it into the
  # `custom_css_<stylesheet>` setting; seeding it here mirrors the corpus the same way
  # PRESENTATION_HEAD_OPTIONS above does, verbatim (RISK-008: no slash/unslash pass).
  PRESENTATION_HEAD_CUSTOM_CSS = "body { color: #333; }\n/* quote \" and backslash \\ */"

  before do
    PRESENTATION_HEAD_OPTIONS.sort.each do |name, value|
      Configuration::Setting.find_or_initialize_by(name: name).update!(value: value)
    end
    Configuration::Setting.find_or_initialize_by(name: "custom_css_#{theme_slug}")
                          .update!(value: PRESENTATION_HEAD_CUSTOM_CSS, autoload: false)
  end

  # What every corpus screen's render enqueues: core/navigation asks for its view module
  # whenever the menu is interactive (navigation.php:955), and the theme's header carries
  # a navigation on every screen. The import map and the preloads are the DEPENDENCIES of
  # that set, which is why the goldens show `@wordpress/interactivity` and not the module
  # itself — an enqueued module gets a real <script> tag in the footer instead.
  ENQUEUED_MODULES = ["@wordpress/block-library/navigation/view"].freeze

  let(:screen) { Presentation::Screen.new(kind: :home) }

  # A Head with every input supplied, exactly as Presentation::Page assembles it.
  def full_head_lines
    @full_head_lines ||= begin
      styles = collector_for(golden("index"))
      head = described_class.new(
        screen: screen, resolution: nil, styles: styles,
        enqueued_script_modules: ENQUEUED_MODULES, site_url: PRESENTATION_HEAD_SITE,
        global_styles: Presentation::GlobalStylesheet.new(theme_slug: theme_slug)
                                                     .css(used_blocks: styles.used),
        block_supports_css: golden_block_supports_css
      )
      normalize(head.to_html).lines.map(&:chomp)
    end
  end

  def theme_slug = Presentation::Theme.active.pick(:slug) || "twentytwentyfive"

  # The block-supports rules are emitted while the TEMPLATE renders, so a Head-only spec
  # has no renderer to fill the store. The golden's own element is used as the input here
  # — this example is about Head's assembly and ordering, and the CONTENT of that element
  # is asserted where it is produced (the block-supports specs), not here.
  def golden_block_supports_css
    lines = golden("index")
    at = lines.index(%(<style id="core-block-supports-inline-css">))
    return nil if at.nil?

    lines[at + 1]
  end

  def head_lines
    @head_lines ||= begin
      head = described_class.new(screen: screen, resolution: nil,
                                 styles: collector_for(golden("index")),
                                 enqueued_script_modules: ENQUEUED_MODULES,
                                 site_url: PRESENTATION_HEAD_SITE)
      normalize(head.to_html).lines.map(&:chomp)
    end
  end

  it "reproduces the head's opening exactly — charset, viewport, robots, title, feed links" do
    expected = golden("index")[3, 6] # lines 4..9, i.e. after <!DOCTYPE>, <html>, <head>
    expect(head_lines.first(6)).to eq(expected)
  end

  it "reproduces the head's closing exactly — REST/RSD links, generator, importmap, fonts" do
    lines = golden("index")
    from = lines.index { |l| l.start_with?('<link rel="https://api.w.org/"') }
    to = lines.index("</head>")
    expected = lines[from...to]
    actual_from = head_lines.index { |l| l.start_with?('<link rel="https://api.w.org/"') }
    expect(head_lines[actual_from..]).to eq(expected)
  end

  it "emits every block stylesheet with the sourceURL trailer the oracle prints" do
    expect(head_lines).to include(
      '<style id="wp-block-site-title-inline-css">',
      "/*# sourceURL=<SITE>/wp-includes/blocks/site-title/style.min.css */"
    )
  end

  # ⚠️ The honest statement of what is still missing. Two `<style>` elements are absent
  # and this test names them rather than letting the screen diff report them as noise:
  #
  #  * `global-styles-inline-css`  — WP_Theme_JSON::get_stylesheet(). The `styling` pack
  #    ports the four-origin CASCADE (Styling::ThemeJsonResolver) but not the stylesheet
  #    GENERATOR, so there is nothing to call.
  #  * `core-block-supports-inline-css` — the layout rules block supports write into the
  #    'block-supports' CSS rules store while the template renders. Empty until the block
  #    renderers register them.
  #
  # ✅ RESOLVED. Both producers now exist — Styling::GlobalStylesheet emits
  # `global-styles`, and the block-supports store emits `core-block-supports` — so this
  # expectation inverted, exactly as its predecessor said it would ("When either lands,
  # this expectation fails, which is the point"). It now asserts the absence of any gap.
  # ⚠️ Head does not PRODUCE `global-styles` or `core-block-supports`; it is HANDED them
  # (Presentation::Page#global_styles / #block_supports_css). A Head constructed without
  # those arguments is not missing them, it was never given them — so this example asserts
  # the only thing that is Head's own: given every input, it prints every element the
  # oracle prints, and in the oracle's order.
  it "is missing nothing the oracle prints, once it is given every input" do
    lines = golden("index")
    to = lines.index("</head>")
    expect(lines[3...to] - full_head_lines).to eq([])
  end

  it "adds nothing the oracle does not print" do
    lines = golden("index")
    to = lines.index("</head>")
    expect(head_lines - lines[3...to]).to eq([])
  end

  # ── wp_maybe_inline_styles(), script-loader.php:3095 ────────────────────────────────
  #
  # ⚠️ DIFFERENTIAL against the goldens, and it has to be: whether a block's stylesheet is
  # inlined or linked is not a property of the block. It is a BUDGET — only styles with a
  # `path` are candidates, sorted ascending by file size and inlined until the running
  # total would exceed 40,000 bytes, at which point the loop breaks (:3164). `/` totals
  # 37,564 path bytes and inlines all of them; the 404 screen totals 41,854, so the
  # largest candidate (`wp-block-navigation`, 20,776) stays external. No amount of reading
  # one screen reveals that, which is why two are compared.
  describe "the inline-style budget" do
    def head_for(golden_name, screen)
      lines = golden(golden_name)
      head = described_class.new(screen: screen, resolution: nil,
                                 styles: collector_for(lines),
                                 enqueued_script_modules: ENQUEUED_MODULES,
                                 site_url: PRESENTATION_HEAD_SITE)
      # The harness masks the cache-buster the same way on both sides (normalizer.rb:76).
      [normalize(head.to_html).gsub(/\bver=\d+\.\d+(\.\d+)?(-\w+)?/, "<TIME>").lines.map(&:chomp),
       lines[3...lines.index("</head>")]]
    end

    it "inlines every candidate on a screen that fits inside the budget" do
      actual, expected = head_for("index", Presentation::Screen.new(kind: :home))
      expect(actual.grep(/\A<link rel='stylesheet'/)).to eq([])
      expect(expected.grep(/\A<link rel='stylesheet'/)).to eq([])
    end

    it "leaves the largest candidate external on a screen that does not" do
      actual, expected = head_for("not-found-404", Presentation::Screen.new(kind: :not_found))
      link = "<link rel='stylesheet' id='wp-block-navigation-css' " \
             "href='<SITE>/wp-includes/blocks/navigation/style.min.css?<TIME>-63330' media='all' />"
      expect(expected).to include(link)
      expect(actual).to include(link)
      # …and in the queue's position, not appended: the whole head lines up once the two
      # elements this example does not SUPPLY are taken out of the golden. `global-styles`
      # and `core-block-supports` are inputs to Head, not products of it (Page passes
      # them), and `head_for` deliberately builds a Head without them — this example is
      # about which stylesheets get inlined versus linked, and nothing else.
      expect(actual).to eq(without_styles(expected, %w[global-styles core-block-supports]))
    end

    # The singular screens are the third data point, and the one that catches a
    # PER-BLOCK accounting: `core/post-comments-form` declares THREE style handles —
    # `["wp-block-post-comments-form", "wp-block-buttons", "wp-block-button"]`
    # (wp-includes/blocks/post-comments-form/block.json:52-56) — so one block
    # contributes 1,991 + 1,395 + 2,559 path bytes, not 1,991. Counting one stylesheet
    # per block leaves the singular total under 40,000 and inlines `wp-block-navigation`;
    # the oracle's total is over, and its golden links it. The budget reads only the
    # queue, never the screen kind, which is why a bare :home screen is enough here.
    it "counts every handle a block enqueues, not one per block" do
      actual, expected = head_for("singular", Presentation::Screen.new(kind: :home))
      link = "<link rel='stylesheet' id='wp-block-navigation-css' " \
             "href='<SITE>/wp-includes/blocks/navigation/style.min.css?<TIME>-63330' media='all' />"
      expect(expected.grep(/\A<link rel='stylesheet'/)).to eq([link])
      expect(actual.grep(/\A<link rel='stylesheet'/)).to eq([link])
    end
  end

  # ── feed_links_extra(), general-template.php:3577-3588 ──────────────────────────────
  #
  # ⚠️ DIFFERENTIAL against the live oracle, because the title in this link is not the
  # stored title: :3582 passes it through `the_title_attribute()`, i.e. get_the_title()'s
  # `Protected: `/`Private: ` prefixes and the whole `the_title` filter chain, then
  # strip_tags and esc_attr (post-template.php:81-97). The four literal screens never show
  # it — `Hello world!` and `Privacy Policy` are fixed points of every stage — and two
  # corpus posts outside them do: the password-protected one and the backslash-title one,
  # whose `\"` reaches the attribute as `\&#8221;`. Their titles are read from the oracle
  # rather than copied here; the other two cases cover the private prefix, strip_tags,
  # convert_chars and capital_P_dangit.
  describe "the singular comments-feed link title" do
    ORACLE_BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"

    # Each case is rendered by the oracle's own the_title_attribute() on a transient
    # WP_Post, exactly the object feed_links_extra() hands it. ⚠️ `filter => 'raw'` is
    # load-bearing: get_post() runs WP_Post::filter('raw') on what it is given, and an
    # object without that marker is re-fetched by ID — ID 0 fetches nothing, and the
    # probe would report an empty title for every case.
    TITLE_SCRIPT = <<~'PHP'
      <?php
      require "%{bootstrap}";
      $cases = json_decode(file_get_contents("%{cases}"), true);
      $out = array();
      foreach ($cases as $i => $c) {
        if (isset($c['slug'])) { $c['title'] = get_page_by_path($c['slug'], OBJECT, 'post')->post_title; }
        $p = new WP_Post((object) array('ID' => 0, 'post_title' => $c['title'], 'filter' => 'raw',
                                        'post_password' => $c['password'], 'post_status' => $c['status']));
        $out[$i] = array('title' => $c['title'],
                         'link' => sprintf('%%1$s %%2$s %%3$s Comments Feed', get_bloginfo('name'), '&raquo;',
                                           the_title_attribute(array('echo' => false, 'post' => $p))));
      }
      echo json_encode($out);
    PHP

    CASES = [
      { "slug" => "password-protected", "password" => "pw", "status" => "publish" },
      { "slug" => "backslash-title-windows-path-cusersthiesfile-txt-regex-ds-literal-n-not-a-newline-latex-frac12-escaped-quote-and",
        "password" => "", "status" => "publish" },
      { "title" => "Quiet one", "password" => "", "status" => "private" },
      { "title" => "Wordpress & <b>friends</b> \"quoted\"", "password" => "", "status" => "publish" },
    ].freeze

    def oracle_titles
      Dir.mktmpdir do |dir|
        File.write("#{dir}/cases.json", JSON.generate(CASES))
        File.write("#{dir}/run.php", format(TITLE_SCRIPT, bootstrap: ORACLE_BOOTSTRAP, cases: "#{dir}/cases.json"))
        JSON.parse(`php #{dir}/run.php`)
      end
    end

    it "prints the title the way the_title_attribute() does" do
      oracle_titles.each_with_index do |result, i|
        c = CASES[i]
        post = Publishing::Article.new(title: result["title"], slug: "t#{i}", status: c["status"] == "private" ? "private" : "published",
                                       published_at: Time.utc(2026, 3, 15, 9, 59), comment_status: "open",
                                       password_digest: c["password"].empty? ? nil : "digest")
        head = described_class.new(screen: Presentation::Screen.new(kind: :single, post: post), resolution: nil,
                                   styles: Composition::StyleCollector.new, site_url: PRESENTATION_HEAD_SITE)
        line = head.to_html.lines.map(&:chomp).find { |l| l.include?("Comments Feed") && l.include?("/t#{i}/feed/") }
        expect(line).not_to be_nil, "no per-post comments feed link for case #{i}"
        expect(line[/title="(.*?)" href=/, 1]).to eq(result["link"]), "case #{i}: #{c.inspect}"
      end
    end
  end
end
