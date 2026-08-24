# frozen_string_literal: true

# Differential harness for the navigation + search + media family.
#
# parity_specs.md: the oracle is the ground truth for every behavioural question, and
# these specs are written as DIFFERENTIAL specs on purpose — "the whole argument for the
# oracle is that the rules were verified by reading, never by executing." A hand-written
# expectation would encode this agent's reading of the PHP; a diff against the running
# oracle encodes the PHP.
module NavigationOracle
  BOOTSTRAP = ENV.fetch("ORACLE_BOOTSTRAP",
                        "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php")

  module_function

  def available? = File.exist?(BOOTSTRAP) && system("which php > /dev/null 2>&1")

  # Renders `markup` through the oracle in a FRESH php process, so that wp_unique_id's
  # counter and WP_Navigation_Block_Renderer's $seen_menu_names start from zero — the
  # same state the rebuild's per-render scope starts from.
  def render(markup, query: nil, page_path: nil)
    php = +""
    php << "$_GET = #{php_array(query)}; $_REQUEST = $_GET;\n" if query
    php << "require #{BOOTSTRAP.inspect};\n"
    php << "if (isset($_GET['s'])) { $GLOBALS['wp_query']->is_search = true; " \
           "$GLOBALS['wp_query']->set('s', $_GET['s']); $GLOBALS['wp_the_query'] = $GLOBALS['wp_query']; }\n"
    # `get_queried_object_id()` is what decides `current-menu-item`; setting the queried
    # object directly is the cheapest way to put the oracle on a given page.
    if page_path
      php << "$__p = get_page_by_path(#{page_path.inspect});\n" \
             "$GLOBALS['wp_query']->queried_object = $__p;\n" \
             "$GLOBALS['wp_query']->queried_object_id = $__p->ID;\n" \
             "$GLOBALS['wp_query']->is_page = true; $GLOBALS['wp_query']->is_singular = true;\n" \
             "$GLOBALS['wp_the_query'] = $GLOBALS['wp_query'];\n"
    end
    php << "$blocks = parse_blocks(#{markup.inspect});\n"
    php << "$out = ''; foreach ($blocks as $b) { $out .= render_block($b); } echo $out;\n"
    out = IO.popen(["php", "-r", php], &:read)
    raise "oracle render failed" unless $?.success?

    out.force_encoding(Encoding::UTF_8)
  end

  def php_array(hash)
    "array(#{hash.map { |k, v| "#{k.to_s.inspect} => #{v.to_s.inspect}" }.join(", ")})"
  end

  # The rebuild's answer, with a fresh RenderContext (hence fresh counters).
  def rebuild(markup, post: nil, query: nil)
    ctx = Composition::RenderContext.new(post: post, query: query)
    Composition::Renderer.render(Composition::Parser.parse(markup), ctx)
  end

  # ── the corpus these specs need, taken from the oracle rather than asserted ─────
  #
  # `spec/rails_helper.rb` runs every example in a transaction against `rebuild_test`,
  # which starts empty. A differential spec therefore has to put the corpus there itself,
  # and the honest source for it is the oracle: hand-writing "there is a page called
  # Sample Page" would make the spec assert this agent's memory of the fixture instead of
  # the fixture. `bin/oracle` owns the oracle's own seeding; this only mirrors it.
  def corpus
    @corpus ||= begin
      php = <<~PHP
        require #{BOOTSTRAP.inspect};
        $pages = array();
        foreach ( get_pages( array( 'sort_column' => 'menu_order,post_title', 'order' => 'asc' ) ) as $p ) {
          $pages[] = array(
            'id' => (int) $p->ID, 'parent_id' => (int) $p->post_parent,
            'menu_order' => (int) $p->menu_order, 'title' => $p->post_title,
            'slug' => $p->post_name, 'published_at' => $p->post_date_gmt,
          );
        }
        $options = array();
        foreach ( array( 'home', 'siteurl', 'blogname', 'blogdescription', 'page_on_front',
                         'show_on_front', 'stylesheet', 'template', 'site_logo' ) as $name ) {
          $options[ $name ] = (string) get_option( $name );
        }
        $navigations = array();
        foreach ( get_posts( array( 'post_type' => 'wp_navigation', 'post_status' => 'publish',
                                    'numberposts' => -1, 'orderby' => 'date', 'order' => 'desc' ) ) as $n ) {
          $navigations[] = array(
            'slug' => $n->post_name, 'title' => $n->post_title,
            'content' => $n->post_content, 'modified' => $n->post_modified_gmt,
          );
        }
        echo wp_json_encode( array( 'pages' => $pages, 'options' => $options,
                                    'navigations' => $navigations ) );
      PHP
      JSON.parse(IO.popen(["php", "-r", php], &:read))
    end
  end

  # Loads that corpus into the test database. Called from `before(:each)` so the
  # transaction rolls it back — a `before(:all)` load happens OUTSIDE the transaction and
  # leaks into every later file, which is a trap another spec in this directory records.
  def seed!
    corpus["options"].each do |name, value|
      setting = Configuration::Setting.find_or_initialize_by(name: name)
      setting.value = value
      setting.autoload = true
      setting.save!(validate: false)
    end

    # The test database is shared, and a `before(:all)` in a neighbouring file can leave
    # pages behind. `core/page-list` renders EVERY published page, so a stray one would
    # appear in the diff; clearing inside the example's transaction is both safe and the
    # only way to guarantee the corpus is the one this file seeded.
    Publishing::Page.delete_all

    ids = {}
    corpus["pages"].each do |page|
      record = Publishing::Page.new(
        title: page["title"], slug: page["slug"], content: "", excerpt: "",
        status: "published", menu_order: page["menu_order"],
        published_at: page["published_at"],
        parent_id: page["parent_id"].zero? ? nil : ids[page["parent_id"]]
      )
      record.save!
      ids[page["id"]] = record.id
    end

    # `core/template-part` prefers a DATABASE part over the theme file, so a leftover row
    # would silently replace the header being tested.
    Composition::Template.parts.delete_all

    # The `wp_navigation` documents, mirrored the same way the pages are: every
    # ref-less `core/navigation` renders the most recently published one as its
    # fallback (class-wp-navigation-fallback.php:70 → navigation.php:1479), so without
    # them the rebuild would render the page-list where the oracle renders the seeded
    # `block-navigation` document.
    Composition::Template.navigations.delete_all
    corpus["navigations"].each do |nav|
      Composition::Template.create!(
        theme_slug: "default", slug: nav["slug"], kind: "navigation",
        title: nav["title"], content: nav["content"], updated_at: nav["modified"]
      )
    end
  end

  # The oracle serves on 127.0.0.1:8099; the rebuild's `home` setting is seeded from it,
  # so absolute self-links already agree. Kept as a seam in case they diverge.
  def normalize(html) = html.to_s
end
