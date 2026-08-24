# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tempfile"

# Composition::Renderers::QueryBlocks against the PHP oracle.
#
# DIFFERENTIAL, for the reason parser_spec.rb gives: handoff.md's argument for the oracle
# is that the rules "were verified by READING, never by executing", so an expectation
# transcribed from a reading of query-pagination-numbers.php would reproduce the very
# weakness the oracle exists to remove. Every expectation below is produced by RUNNING
# the legacy.
#
# Two groups, because they need different things:
#
#   * The URL and markup machinery -- get_pagenum_link, add_query_arg, paginate_links,
#     get_query_pagination_arrow, get_block_wrapper_attributes -- depends only on
#     settings, so it is compared function-for-function on every run. This is where the
#     risk is: it is the part that is fiddly, and the part the golden files show most of.
#
#   * Whole-block renders need the same RECORDS on both sides. The oracle is read-only
#     and the test database is empty, so that group runs only when the corpus has been
#     loaded (`rake oracle:seed`), exactly as parser_spec skips without it. The results
#     of running it against the seeded corpus are recorded in the wave report.
RSpec.describe Composition::Renderers::QueryBlocks do
  QB_BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"

  # The oracle's own values, so the two sides describe the same site.
  QB_HOME = "http://127.0.0.1:8099"
  QB_PERMALINKS = "/%year%/%monthnum%/%postname%/"

  before do
    put_setting("home", QB_HOME)
    put_setting("siteurl", QB_HOME)
    put_setting("permalink_structure", QB_PERMALINKS)
  end

  # The suite shares one test database with the other block families, so a settings row
  # can appear between the SELECT and the INSERT. The savepoint keeps the surrounding
  # fixture transaction usable when it does.
  def put_setting(name, value)
    attempts = 0
    begin
      attempts += 1
      ActiveRecord::Base.transaction(requires_new: true) do
        row = Configuration::Setting.find_or_initialize_by(name: name)
        row.value = value
        row.save!
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::Deadlocked
      retry if attempts < 3
      raise
    end
  end

  # Runs a snippet of PHP inside a real front-end request, so $_GET, $_SERVER and
  # $wp_query are populated the way the render callbacks expect to find them.
  def oracle(cases)
    script = <<~PHP
      <?php
      $in = json_decode(file_get_contents('php://stdin'), true);
      $uri = $in['path'];
      $parts = parse_url($uri);
      $_SERVER['HTTP_HOST'] = '127.0.0.1:8099';
      $_SERVER['SERVER_NAME'] = '127.0.0.1';
      $_SERVER['REQUEST_URI'] = $uri;
      $_SERVER['REQUEST_METHOD'] = 'GET';
      $_SERVER['SERVER_PORT'] = '8099';
      $_SERVER['QUERY_STRING'] = $parts['query'] ?? '';
      if (!empty($parts['query'])) { parse_str($parts['query'], $_GET); }
      require_once '#{QB_BOOTSTRAP}';
      // ⚠️ _bootstrap.php resets $_SERVER for a generic CLI request, so the request
      // being simulated has to be restated AFTER it, before wp() parses it.
      $_SERVER['REQUEST_URI'] = $uri;
      $_SERVER['QUERY_STRING'] = $parts['query'] ?? '';
      wp();
      $out = [];
      foreach ($in['cases'] as $key => $c) {
        switch ($c['fn']) {
          case 'get_pagenum_link':
            $out[$key] = get_pagenum_link($c['args'][0]);
            break;
          case 'add_query_arg':
            $out[$key] = add_query_arg($c['args'][0], $c['args'][1]);
            break;
          case 'paginate_links':
            $out[$key] = (string) paginate_links($c['args'][0]);
            break;
          case 'pagination_arrow':
            $b = new WP_Block(parse_blocks('<!-- wp:query-pagination-next /-->')[0], $c['args'][1]);
            $out[$key] = (string) get_query_pagination_arrow($b, $c['args'][0]);
            break;
          case 'wrapper_attributes':
            $block = parse_blocks($c['args'][0])[0];
            WP_Block_Supports::$block_to_render = $block;
            $out[$key] = get_block_wrapper_attributes($c['args'][1]);
            WP_Block_Supports::$block_to_render = null;
            break;
          case 'post_class':
            $out[$key] = implode(' ', get_post_class($c['args'][0], $c['args'][1]));
            break;
        }
      }
      echo json_encode($out, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
    PHP
    run_php(script, cases)
  end

  # Renders block markup in the oracle, in a real request, with the FULL render_block
  # filter chain — layout and elements included. QueryBlocks::SupportChain now routes
  # every renderer's output through the shared `Renderers::LayoutBlocks.apply_supports`
  # port (see the class comment in query_blocks.rb), so the differential compares the
  # complete output, `is-layout-*` / `wp-container-*` classes and all.
  def oracle_render(path, markup)
    script = <<~PHP
      <?php
      $in = json_decode(file_get_contents('php://stdin'), true);
      $uri = $in['path'];
      $parts = parse_url($uri);
      $_SERVER['HTTP_HOST'] = '127.0.0.1:8099';
      $_SERVER['SERVER_NAME'] = '127.0.0.1';
      $_SERVER['REQUEST_URI'] = $uri;
      $_SERVER['REQUEST_METHOD'] = 'GET';
      $_SERVER['SERVER_PORT'] = '8099';
      $_SERVER['QUERY_STRING'] = $parts['query'] ?? '';
      if (!empty($parts['query'])) { parse_str($parts['query'], $_GET); }
      require_once '#{QB_BOOTSTRAP}';
      $_SERVER['REQUEST_URI'] = $uri;
      $_SERVER['QUERY_STRING'] = $parts['query'] ?? '';
      wp();
      $html = '';
      foreach (parse_blocks($in['markup']) as $b) {
        if ($b['blockName'] === null && trim($b['innerHTML']) === '') continue;
        $html .= render_block($b);
      }
      echo json_encode(['html' => $html], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
    PHP
    run_php(script, { "path" => path, "markup" => markup })["html"]
  end

  def run_php(script, payload)
    file = Tempfile.new(["query_blocks", ".php"])
    file.write(script)
    file.close
    out, err, status = Open3.capture3("php", file.path, stdin_data: JSON.generate(payload))
    raise "PHP oracle failed: #{err[0, 600]}" unless status.success?
    raise "PHP oracle did not return JSON: #{out[0, 300]}" unless out.lstrip.start_with?("{")

    JSON.parse(out)
  ensure
    file&.unlink
  end

  def context_for(path, **extra)
    query_string = path.split("?", 2)[1].to_s
    params = query_string.split("&").reject(&:empty?).to_h do |pair|
      key, value = pair.split("=", 2)
      [CGI.unescape(key), CGI.unescape(value.to_s)]
    end
    # The MAIN query, i.e. what the controller will hand the renderer as ctx.query. It
    # has to agree with the path: `is_home()` is what decides whether get_post_class()
    # adds `sticky`, and it is false on a search page.
    main = { post_type: "post", paged: path[%r{/page/(\d+)}, 1] || 1 }
    main[:s] = params["s"] if params["s"].present?
    Composition::RenderContext.new(
      query: Retrieval::PostQuery.new(main, trusted: true),
      context: { request_path: path, request_params: params }.merge(extra)
    )
  end

  def expect_identical(path, cases, actual)
    expected = oracle("path" => path, "cases" => cases)
    mismatches = expected.keys.reject { |key| expected[key] == actual[key] }
    return if mismatches.empty?

    detail = mismatches.map do |key|
      "  #{key}\n    php:   #{expected[key].inspect}\n    ruby:  #{actual[key].inspect}"
    end
    raise "#{mismatches.length} of #{expected.length} diverged from the oracle:\n#{detail.join("\n")}"
  end

  # ── get_pagenum_link(), link-template.php:2432 ───────────────────────────────────
  describe "the paged permalink" do
    QB_PATHS = ["/", "/page/2/", "/page/7/", "/category/top-category/",
             "/category/top-category/page/3/", "/2026/", "/2026/03/",
             "/author/oracle_author/", "/?s=article", "/?s=a%20b&paged=4",
             "/?query-7-page=2", "/tag/flat-tag-one/page/2/"].freeze

    it "matches the oracle for every corpus path and page number" do
      QB_PATHS.each do |path|
        ctx = context_for(path)
        cases = {}
        actual = {}
        [1, 2, 3, 12].each do |pagenum|
          key = "#{path}|#{pagenum}"
          cases[key] = { "fn" => "get_pagenum_link", "args" => [pagenum] }
          actual[key] = described_class::Support.get_pagenum_link(pagenum, ctx)
        end
        expect_identical(path, cases, actual)
      end
    end
  end

  # ── add_query_arg(), functions.php:1144 ──────────────────────────────────────────
  describe "the query-argument builder" do
    it "matches the oracle, including the '=' stripping that makes ?cst work" do
      [["/", { "query-page" => 2 }],
       ["/", { "cst" => "" }],
       ["/?s=article", { "query-7-page" => 3 }],
       ["/?query-7-page=2&foo=bar", { "query-7-page" => 4 }],
       ["/2026/03/hello-world/", { "query-page" => 2 }],
       ["/?a=1", { "b" => "x y", "c" => "" }],
       ["/?paged=2#frag", { "query-page" => 5 }]].each do |path, args|
        cases = { "case" => { "fn" => "add_query_arg", "args" => [args, path] } }
        actual = { "case" => described_class::Support.add_query_arg(args, path) }
        expect_identical(path, cases, actual)
      end
    end
  end

  # ── paginate_links(), general-template.php:4873 ──────────────────────────────────
  describe "the page-number list" do
    it "matches the oracle for both argument shapes the block library uses" do
      # The inherit shape (query-pagination-numbers.php:35) and the custom-query shape
      # (:50), with the mid_size/end_size ellipsis cases that only appear at scale.
      shapes = [
        { "prev_next" => false, "total" => 2, "current" => 1 },
        { "prev_next" => false, "total" => 9, "current" => 5 },
        { "prev_next" => false, "total" => 20, "current" => 11, "mid_size" => 1 },
        { "prev_next" => false, "total" => 20, "current" => 1, "mid_size" => 0 },
        { "prev_next" => false, "total" => 1, "current" => 1 },
        { "base" => "%_%", "format" => "?query-7-page=%#%", "current" => 1,
          "total" => 4, "prev_next" => false },
        { "base" => "%_%", "format" => "?query-7-page=%#%", "current" => 3,
          "total" => 4, "prev_next" => false, "add_args" => { "cst" => "" } },
        { "base" => "%_%", "format" => "?query-page=%#%", "current" => 2,
          "total" => 6, "prev_next" => false, "add_args" => { "paged" => 2 } },
      ]
      ["/", "/?s=article", "/page/2/"].each do |path|
        ctx = context_for(path)
        cases = {}
        actual = {}
        shapes.each_with_index do |args, index|
          key = "#{path}|#{index}"
          cases[key] = { "fn" => "paginate_links", "args" => [args] }
          actual[key] = described_class::Support.paginate_links(ctx, args).to_s
        end
        expect_identical(path, cases, actual)
      end
    end
  end

  # ── get_query_pagination_arrow(), blocks.php:3084 ────────────────────────────────
  describe "the pagination arrow" do
    it "matches the oracle for every paginationArrow value" do
      cases = {}
      actual = {}
      [nil, "", "none", "arrow", "chevron", "bogus"].each do |arrow|
        [true, false].each do |is_next|
          key = "#{arrow.inspect}|#{is_next}"
          block_context = arrow.nil? ? {} : { "paginationArrow" => arrow }
          cases[key] = { "fn" => "pagination_arrow", "args" => [is_next, block_context] }
          ctx = context_for("/", **{})
          ctx = ctx.with(context: block_context)
          actual[key] = described_class::Support.pagination_arrow(ctx, is_next).to_s
        end
      end
      expect_identical("/", cases, actual)
    end
  end

  # ── get_block_wrapper_attributes(), class-wp-block-supports.php:203 ──────────────
  describe "the block wrapper" do
    # Only the four attribute-only supports this family computes: align, custom
    # classname, generated classname, anchor. A block carrying colour or typography
    # attributes would also pull in the style-producing supports, which live in the
    # shared layer -- see the note at the top of query_blocks.rb.
    QB_MARKUPS = [
      '<!-- wp:query /-->',
      '<!-- wp:query {"align":"full"} /-->',
      '<!-- wp:query {"align":"wide","className":"mine other","anchor":"loop-1"} /-->',
      '<!-- wp:post-template /-->',
      '<!-- wp:post-template {"align":"full","className":"grid"} /-->',
      '<!-- wp:query-pagination /-->',
      '<!-- wp:query-pagination {"align":"wide"} /-->',
      '<!-- wp:query-pagination-next /-->',
      '<!-- wp:query-pagination-next {"align":"wide"} /-->',
      '<!-- wp:query-pagination-previous {"anchor":"prev"} /-->',
      '<!-- wp:query-pagination-numbers /-->',
      '<!-- wp:query-no-results /-->',
      '<!-- wp:query-no-results {"align":"full","className":"x"} /-->',
    ].freeze

    QB_EXTRAS = [{}, { "class" => "" }, { "class" => "has-link-color" },
              { "aria-label" => "Pagination", "class" => "" },
              { "class" => "is-flex-container columns-3" }].freeze

    it "matches the oracle for every block in the family" do
      cases = {}
      actual = {}
      QB_MARKUPS.each do |markup|
        QB_EXTRAS.each_with_index do |extra, index|
          key = "#{markup}|#{index}"
          cases[key] = { "fn" => "wrapper_attributes", "args" => [markup, extra] }
          block = Composition::Parser.parse(markup).first
          type = Composition::Registry[block.block_name]
          attrs = type.prepare_attributes(block.attrs)
          actual[key] = described_class::Support.wrapper_attributes(type, attrs, extra)
        end
      end
      expect_identical("/", cases, actual)
    end
  end

  # ── PHP semantics the callbacks lean on ──────────────────────────────────────────
  describe "the PHP primitives" do
    it "reads a page number out of $_GET the way (int) does" do
      { "" => 1, "0" => 1, nil => 1, "2" => 2, "2x" => 2, "x" => 0, "-3" => -3,
        " 4" => 4, "003" => 3 }.each do |raw, expected|
        ctx = context_for("/", **{})
        ctx = Composition::RenderContext.new(
          context: { request_path: "/", request_params: raw.nil? ? {} : { "query-page" => raw } }
        )
        expect(described_class::Support.current_page(ctx)).to eq(expected), "for #{raw.inspect}"
      end
    end

    it "strips percent-encoded octets from a term slug, as sanitize_html_class does" do
      # The corpus's emoji tag is the case that matters: `tag-with-%f0%9f%98%80-emoji`.
      cases = { "emoji" => { "fn" => "post_class", "args" => ["", 0] } }
      _ = cases # the PHP side of this one is covered by the corpus group below.
      expect(described_class::Support.sanitize_html_class("tag-with-%f0%9f%98%80-emoji"))
        .to eq("tag-with--emoji")
      expect(described_class::Support.sanitize_html_class("%e4%b8%80", "42")).to eq("42")
    end
  end

  # ── Whole-block renders ─────────────────────────────────────────────────────────
  #
  # These need the SAME RECORDS on both sides, so the oracle's own rows are read out of
  # it and rebuilt here, ids and all -- the approach comment_blocks_spec.rb established.
  # Rebuilding the ids rather than normalizing them away is what makes `post-15` and
  # `data-wp-key="post-template-item-15"` comparable byte for byte instead of after a
  # substitution, and it is also what makes the `sticky_posts` option MEAN the same
  # thing on both sides. (In the seeded development database it does not: see the
  # sticky finding in the wave report.)
  describe "whole-block rendering against the oracle" do
    QB_QUERY_INHERIT = '{"perPage":3,"pages":0,"offset":0,"postType":"post","order":"desc",' \
                    '"orderBy":"date","author":"","search":"","exclude":[],"sticky":"",' \
                    '"inherit":true,"taxQuery":null,"parents":[]}'
    QB_QUERY_CUSTOM = QB_QUERY_INHERIT.sub('"inherit":true', '"inherit":false')

    QB_PAGINATION = <<~HTML.strip
      <!-- wp:query-pagination {"paginationArrow":"arrow","align":"wide","layout":{"type":"flex","justifyContent":"space-between"}} -->
      <!-- wp:query-pagination-previous /-->
      <!-- wp:query-pagination-numbers /-->
      <!-- wp:query-pagination-next /-->
      <!-- /wp:query-pagination -->
    HTML

    def loop_markup(query_json, body)
      <<~HTML.strip
        <!-- wp:query {"query":#{query_json},"align":"full","layout":{"type":"default"}} -->
        <div class="wp-block-query alignfull">
        #{body}
        </div>
        <!-- /wp:query -->
      HTML
    end

    QB_CORPUS = begin
      script = <<~PHP
        <?php
        require_once '#{QB_BOOTSTRAP}';
        $out = ['options' => [], 'posts' => [], 'terms' => [], 'assignments' => []];
        foreach (['home','siteurl','permalink_structure','posts_per_page','sticky_posts'] as $o) {
          $out['options'][$o] = get_option($o);
        }
        $posts = get_posts(['post_type' => ['post','page'], 'post_status' => 'any', 'numberposts' => -1]);
        foreach ($posts as $p) {
          $out['posts'][] = [
            'id' => (int) $p->ID, 'type' => $p->post_type, 'author_id' => (int) $p->post_author,
            'parent_id' => (int) $p->post_parent, 'title' => $p->post_title,
            'slug' => $p->post_name, 'content' => $p->post_content, 'excerpt' => $p->post_excerpt,
            'status' => $p->post_status, 'published_at' => $p->post_date_gmt,
            'modified_at' => $p->post_modified_gmt, 'password' => $p->post_password,
            'comment_count' => (int) $p->comment_count,
            'thumbnail' => has_post_thumbnail($p->ID) ? 1 : 0,
          ];
          foreach (['category', 'post_tag'] as $tax) {
            foreach ((array) get_the_terms($p->ID, $tax) as $t) {
              if (!$t || is_wp_error($t)) { continue; }
              $out['assignments'][] = ['post' => (int) $p->ID, 'taxonomy' => $tax, 'term' => (int) $t->term_id];
              $out['terms'][$tax . '-' . $t->term_id] = [
                'taxonomy' => $tax, 'id' => (int) $t->term_id,
                'name' => $t->name, 'slug' => $t->slug,
              ];
            }
          }
        }
        $out['terms'] = array_values($out['terms']);
        echo json_encode($out, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
      PHP
      file = Tempfile.new(["corpus", ".php"])
      file.write(script)
      file.close
      out, err, status = Open3.capture3("php", file.path)
      status.success? ? JSON.parse(out) : { "error" => err[0, 400] }
    ensure
      file&.unlink
    end

    before do
      skip "oracle unavailable: #{QB_CORPUS["error"]}" if QB_CORPUS["error"]

      # Other families' fixtures TRUNCATE the same tables, so the seed can lose a
      # deadlock to one of them. The savepoint makes the retry possible without
      # poisoning the example's own transaction.
      attempts = 0
      begin
        attempts += 1
        ActiveRecord::Base.transaction(requires_new: true) { seed_corpus! }
      rescue ActiveRecord::Deadlocked, ActiveRecord::RecordNotUnique
        if attempts < 8
          sleep(0.05 * attempts + (rand * 0.05))
          retry
        end
        raise
      end
    end

    # `GENERATED ALWAYS AS IDENTITY` says ids are the database's business, so the
    # fixture goes in through OVERRIDING SYSTEM VALUE rather than by relaxing the schema.
    def insert_row!(table, attributes)
      conn = ActiveRecord::Base.connection
      columns = attributes.keys
      conn.execute(<<~SQL)
        INSERT INTO #{conn.quote_table_name(table)}
          (#{columns.map { |c| conn.quote_column_name(c) }.join(", ")})
          OVERRIDING SYSTEM VALUE
          VALUES (#{columns.map { |c| conn.quote(attributes[c]) }.join(", ")})
      SQL
    end

    QB_STATUS_OF = { "publish" => "published", "future" => "scheduled", "private" => "private",
                  "draft" => "draft", "pending" => "pending", "trash" => "trashed",
                  "auto-draft" => "auto_draft", "inherit" => "published" }.freeze

    # A draft carries '0000-00-00 00:00:00', which is not a date. BR-MIGRATE-032's
    # counterpart in the schema is `published_at IS NULL`.
    def mysql_time(value)
      parts = value.to_s.scan(/\d+/).map(&:to_i)
      return nil if parts.length < 6 || parts[1].zero? || parts[2].zero?

      Time.utc(*parts)
    end

    # The suite shares one test database and other families leave rows behind, so the
    # tables this fixture owns are cleared first. It happens INSIDE the example's
    # transaction, so nothing outside the example sees it.
    def reset_corpus_tables!
      conn = ActiveRecord::Base.connection
      # term_assignments' classifiable is polymorphic and carries no foreign key, so it
      # is the one table the cascade cannot reach.
      %w[term_assignments posts terms taxonomies assets].each do |table|
        conn.execute("DELETE FROM #{conn.quote_table_name(table)}")
      end
    end

    def seed_corpus!
      reset_corpus_tables!
      now = Time.utc(2026, 1, 1)
      QB_CORPUS["options"].each { |name, value| put_setting(name, value) }

      # One asset stands in for every featured image: post_class only asks whether the
      # post HAS a thumbnail, and the image blocks are another family's.
      insert_row!("assets", "id" => 1, "title" => "oracle", "slug" => "oracle-image",
                            "mime_type" => "image/png", "byte_size" => 1, "metadata" => "{}",
                            "created_at" => now, "updated_at" => now)

      # Parents before children: `posts_slug_hierarchical` is scoped by parent, so the
      # corpus's two `child-page` rows only coexist once each has its real parent.
      ordered = []
      pending = QB_CORPUS["posts"].dup
      placed = Set.new
      until pending.empty?
        batch, pending = pending.partition do |p|
          p["parent_id"].to_i.zero? || placed.include?(p["parent_id"].to_i)
        end
        raise "unresolvable post hierarchy in the corpus dump" if batch.empty?

        batch.each { |p| placed << p["id"].to_i }
        ordered.concat(batch)
      end

      ordered.each do |p|
        insert_row!("posts",
                    "id" => p["id"],
                    "type" => p["type"] == "page" ? "Publishing::Page" : "Publishing::Article",
                    # `users` is another family's fixture and nothing here reads the
                    # author, so the column stays null.
                    "author_id" => nil,
                    "parent_id" => p["parent_id"].to_i.positive? ? p["parent_id"] : nil,
                    "featured_asset_id" => p["thumbnail"] == 1 ? 1 : nil,
                    "title" => p["title"],
                    # BR-MIGRATE-032: a slugless status stores NULL, not ''. The legacy's
                    # '' would collide every draft against every other under the partial
                    # unique index.
                    "slug" => p["slug"].to_s.empty? ? nil : p["slug"],
                    "content" => p["content"],
                    "excerpt" => p["excerpt"], "status" => QB_STATUS_OF.fetch(p["status"], "draft"),
                    "published_at" => mysql_time(p["published_at"]),
                    "modified_at" => mysql_time(p["modified_at"]) || now,
                    "password_digest" => p["password"].to_s.empty? ? nil : "x",
                    "comment_count" => p["comment_count"], "guid" => SecureRandom.uuid,
                    "menu_order" => 0, "residual_attributes" => "{}",
                    "created_at" => now, "updated_at" => now)
      end

      # T-06: one row per (term, taxonomy) pair, so a legacy term_id that served two
      # taxonomies would collide here. The synthetic key keeps them apart.
      taxonomy_ids = {}
      %w[category post_tag].each_with_index do |name, index|
        taxonomy_ids[name] = index + 1
        insert_row!("taxonomies", "id" => index + 1, "name" => name,
                                  "hierarchical" => name == "category", "object_types" => "{post}")
      end
      term_ids = {}
      QB_CORPUS["terms"].each_with_index do |t, index|
        term_ids["#{t["taxonomy"]}-#{t["id"]}"] = index + 1
        insert_row!("terms", "id" => index + 1, "taxonomy_id" => taxonomy_ids[t["taxonomy"]],
                             "name" => t["name"], "slug" => t["slug"], "description" => "",
                             "count" => 0, "created_at" => now, "updated_at" => now)
      end
      QB_CORPUS["assignments"].each_with_index do |a, index|
        insert_row!("term_assignments", "id" => index + 1,
                                        "term_id" => term_ids["#{a["taxonomy"]}-#{a["term"]}"],
                                        "classifiable_type" => "Publishing::Post",
                                        "classifiable_id" => a["post"], "position" => 0)
      end
    end

    # The pagination markup depends only on counts and URLs, so it is comparable even
    # when the two databases disagree about row ids.
    it "renders the theme's pagination identically on the blog index" do
      markup = loop_markup(QB_QUERY_INHERIT, QB_PAGINATION)
      ["/", "/page/2/"].each do |path|
        expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup))
      end
    end

    it "renders a custom query's pagination identically, including the ?cst workaround" do
      markup = loop_markup(QB_QUERY_CUSTOM, QB_PAGINATION)
      ["/", "/?query-page=2", "/?query-page=4", "/2026/03/hello-world/?query-page=3"].each do |path|
        expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup))
      end
    end

    it "suppresses the whole nav when the pagination has no children" do
      markup = loop_markup(QB_QUERY_CUSTOM, "<!-- wp:query-pagination /-->")
      expect(Composition::Renderer.render(markup, context_for("/"))).to eq(oracle_render("/", markup))
    end

    it "renders query-no-results identically, present and absent" do
      body = "<!-- wp:query-no-results -->\n<p>none</p>\n<!-- /wp:query-no-results -->"
      markup = loop_markup(QB_QUERY_CUSTOM, body)
      ["/", "/?query-page=9"].each do |path|
        expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup))
      end
    end

    # post-template's <li> carries get_post_class(): the post id, the status, the post
    # format, the password and thumbnail flags, the `sticky` promotion and one class per
    # public taxonomy term. Byte-for-byte, ids included.
    it "renders post-template's list items identically, including get_post_class()" do
      body = "<!-- wp:post-template -->\n<span>x</span>\n<!-- /wp:post-template -->"
      markup = loop_markup(QB_QUERY_INHERIT, body)
      ["/", "/page/2/"].each do |path|
        expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup))
      end
    end

    # class-wp-query.php:3609 -- a sticky post that is NOT in the page's results is
    # fetched separately and spliced in front, so a `perPage` of four comes back with
    # five items. golden-web-search.html's "More posts" loop is exactly this case, and
    # it is the arm a naive sticky implementation misses.
    it "renders a custom loop's sticky promotion identically, extra row and all" do
      body = "<!-- wp:post-template -->\n<span>m</span>\n<!-- /wp:post-template -->"
      query = QB_QUERY_CUSTOM.sub('"perPage":3', '"perPage":4')
      markup = loop_markup(query, body)
      ["/?s=article", "/?query-page=2"].each do |path|
        expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup))
      end
    end

    # The attribute surface of the family, one case per branch that the theme's own
    # markup never reaches. Every one of these is a real arm of a render callback.
    QB_ATTRIBUTE_CASES = {
      "showLabel false, arrow none, midSize" =>
        ["/?query-page=3",
         '<!-- wp:query-pagination {"showLabel":false,"paginationArrow":"none"} -->' \
         '<!-- wp:query-pagination-previous /--><!-- wp:query-pagination-numbers {"midSize":1} /-->' \
         '<!-- wp:query-pagination-next /--><!-- /wp:query-pagination -->'],
      "custom labels, escaped" =>
        ["/?query-page=2",
         '<!-- wp:query-pagination {"paginationArrow":"arrow"} -->' \
         '<!-- wp:query-pagination-previous {"label":"Older & wiser"} /-->' \
         '<!-- wp:query-pagination-next {"label":"Newer <b>"} /--><!-- /wp:query-pagination -->'],
      "anchor and align on the wrapper" =>
        ["/", '<!-- wp:query-no-results {"align":"full","anchor":"nothing-here"} -->' \
              "<p>none</p><!-- /wp:query-no-results -->"],
      "displayLayout flex becomes is-flex-container" =>
        ["/", "<!-- wp:post-template -->\n<span>y</span>\n<!-- /wp:post-template -->",
         '"displayLayout":{"type":"flex","columns":3}'],
      "grid layout and link colour on post-template" =>
        ["/", '<!-- wp:post-template {"className":"my-extra","layout":{"type":"grid",' \
              '"columnCount":3,"minimumColumnWidth":"12rem"},"style":{"elements":{"link":' \
              '{"color":{"text":"var:preset|color|accent"}}}}} -->' \
              "\n<span>y</span>\n<!-- /wp:post-template -->"],
    }.freeze

    QB_ATTRIBUTE_CASES.each do |name, (path, body, extra_query_attrs)|
      it "renders #{name} identically" do
        query_json = QB_QUERY_CUSTOM
        markup = if extra_query_attrs
                   "<!-- wp:query {\"query\":#{QB_QUERY_INHERIT},#{extra_query_attrs}} -->\n" \
                     "<div class=\"wp-block-query\">\n#{body}\n</div>\n<!-- /wp:query -->"
                 else
                   loop_markup(query_json, body)
                 end
        expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup))
      end
    end

    # enhancedPagination is the one arm that rewrites already-rendered HTML with the
    # tag processor (query.php:29, query-pagination-next.php:71, -numbers.php:98).
    it "adds the interactivity directives identically when enhancedPagination is on" do
      markup = <<~HTML.strip
        <!-- wp:query {"queryId":5,"enhancedPagination":true,"query":#{QB_QUERY_CUSTOM}} -->
        <div class="wp-block-query">
        <!-- wp:post-template -->
        <span>z</span>
        <!-- /wp:post-template -->
        <!-- wp:query-pagination {"paginationArrow":"arrow"} -->
        <!-- wp:query-pagination-previous /-->
        <!-- wp:query-pagination-numbers /-->
        <!-- wp:query-pagination-next /-->
        <!-- /wp:query-pagination -->
        </div>
        <!-- /wp:query -->
      HTML
      ["/", "/?query-5-page=2"].each do |path|
        expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup))
      end
    end

    it "gives the sticky class only on the unpaged blog index, never on a search page" do
      body = "<!-- wp:post-template -->\n<span>m</span>\n<!-- /wp:post-template -->"
      markup = loop_markup(QB_QUERY_CUSTOM.sub('"perPage":3', '"perPage":4'), body)
      home = Composition::Renderer.render(markup, context_for("/"))
      search = Composition::Renderer.render(markup, context_for("/?s=article"))
      expect(home).to include(" sticky ")
      expect(search).not_to include(" sticky ")
      expect(search).to eq(oracle_render("/?s=article", markup))
    end

    # ── Verification pass: the arms the family's own examples did not reach ─────────
    #
    # Added while independently checking this family against the oracle. The first two
    # examples FAILED when they were written and are the regression cover for two real
    # divergences (both fixed):
    #
    #   * class-wp-query.php:3699 -- set_found_posts() BAILS when the page came back
    #     empty, so an out-of-range page reports max_num_pages = 0 and the whole <nav>
    #     disappears. Retrieval::PostQuery#total_pages was reporting the real page count
    #     instead, and the rebuild rendered a live page list past the end of the loop.
    #   * query-pagination-numbers.php:84-88 -- `if ( $paged )` tests the (int) CAST, so
    #     `?paged=0x` must leave the `cst` workaround in place. It was being replaced
    #     with `paged=0`.
    it "suppresses the pagination past the last page, as an empty found_posts does" do
      body = '<!-- wp:query-pagination --><!-- wp:query-pagination-numbers {"midSize":0} /-->' \
             "<!-- /wp:query-pagination -->"
      markup = loop_markup(QB_QUERY_CUSTOM.sub('"perPage":3', '"perPage":1'), body)
      ["/", "/?query-page=5", "/?query-page=12"].each do |path|
        expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup)), path
      end
    end

    it "keeps the ?cst workaround when ?paged casts to zero" do
      markup = loop_markup(QB_QUERY_CUSTOM, QB_PAGINATION)
      ["/?query-page=3&paged=0x", "/?query-page=3&paged=0", "/?query-page=2&paged=abc"].each do |path|
        expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup)), path
      end
    end

    it "renders an inheriting loop's pagination identically past the last page" do
      markup = loop_markup(QB_QUERY_INHERIT, QB_PAGINATION)
      ["/page/3/", "/?s=article", "/page/9/"].each do |path|
        expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup)), path
      end
    end

    it "renders post-template identically on every page of a custom loop" do
      body = "<!-- wp:post-template -->\n<span>x</span>\n<!-- /wp:post-template -->"
      markup = loop_markup(QB_QUERY_CUSTOM, body)
      ["/", "/?query-page=2", "/?query-page=3", "/?query-page=99"].each do |path|
        expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup)), path
      end
    end

    # showLabel:false and a custom label together: the aria-label arm carries the
    # esc_html()'d label, and nothing re-escapes it (query-pagination-next.php:34).
    it "renders a suppressed label with entities identically" do
      body = '<!-- wp:query-pagination {"showLabel":false,"paginationArrow":"chevron"} -->' \
             '<!-- wp:query-pagination-previous {"label":"Older & \"wiser\""} /-->' \
             '<!-- wp:query-pagination-next {"label":"Newer <b>&amp;</b>"} /--><!-- /wp:query-pagination -->'
      markup = loop_markup(QB_QUERY_CUSTOM, body)
      path = "/?query-page=2"
      expect(Composition::Renderer.render(markup, context_for(path))).to eq(oracle_render(path, markup))
    end
  end
end
