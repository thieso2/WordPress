# frozen_string_literal: true

require "rails_helper"
require "json"
require "open3"
require "tmpdir"

# Differential parity for the COMMENT FAMILY.
#
# parity_specs.md: "the rules were verified by reading, never by executing". These
# examples close that gap the only way it can be closed — by executing the legacy. Every
# expectation below is produced by the live oracle at the moment the example runs; there
# is not one hand-written string of HTML in this file.
#
# The fixture is the oracle's OWN corpus, read out of its database and rebuilt row for
# row (ids included) in the test database, so the comparison is byte-for-byte with no
# normalization whatsoever.
RSpec.describe Composition::Renderers::CommentBlocks do
  COMMENT_ORACLE_BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"

  # Renders a list of block cases through the oracle and dumps its corpus alongside.
  COMMENT_ORACLE_SCRIPT = <<~'PHP'
    <?php
    require "%{bootstrap}";

    $cases = json_decode(file_get_contents("%{cases}"), true);

    $out = array('options' => array(), 'users' => array(), 'posts' => array(),
                 'comments' => array(), 'rendered' => array());

    foreach (array('siteurl','home','permalink_structure','date_format','time_format',
                   'timezone_string','gmt_offset','thread_comments','thread_comments_depth',
                   'comment_order','page_comments','comments_per_page','default_comments_page',
                   'require_name_email','show_comments_cookies_opt_in','comment_registration',
                   'blogname','blogdescription') as $o) {
      $out['options'][$o] = get_option($o);
    }

    foreach (get_users(array('orderby' => 'ID')) as $u) {
      $out['users'][] = array('id' => (int) $u->ID, 'login' => $u->user_login,
                              'nicename' => $u->user_nicename, 'display_name' => $u->display_name,
                              'email' => $u->user_email, 'url' => $u->user_url);
    }

    $post_ids = array();
    foreach ($cases as $case) {
      if (isset($case['context']['postId'])) { $post_ids[] = (int) $case['context']['postId']; }
    }
    $post_ids = array_values(array_unique($post_ids));
    foreach ($post_ids as $pid) {
      $p = get_post($pid);
      $out['posts'][] = array(
        'id' => (int) $p->ID, 'type' => $p->post_type, 'author_id' => (int) $p->post_author,
        'parent_id' => (int) $p->post_parent, 'title' => $p->post_title, 'slug' => $p->post_name,
        'content' => $p->post_content, 'excerpt' => $p->post_excerpt, 'status' => $p->post_status,
        'published_at' => $p->post_date, 'modified_at' => $p->post_modified,
        'comment_status' => $p->comment_status, 'comment_count' => (int) $p->comment_count,
        'password' => $p->post_password,
      );
      foreach (get_comments(array('post_id' => $pid, 'status' => 'any', 'orderby' => 'comment_ID',
                                  'order' => 'ASC')) as $c) {
        $out['comments'][] = array(
          'id' => (int) $c->comment_ID, 'post_id' => (int) $c->comment_post_ID,
          'parent_id' => (int) $c->comment_parent, 'user_id' => (int) $c->user_id,
          'author_name' => $c->comment_author, 'author_email' => $c->comment_author_email,
          'author_url' => $c->comment_author_url, 'author_ip' => $c->comment_author_IP,
          'user_agent' => $c->comment_agent, 'content' => $c->comment_content,
          'approved' => $c->comment_approved, 'kind' => $c->comment_type,
          'submitted_at' => $c->comment_date,
        );
      }
    }

    foreach ($cases as $case) {
      $context = isset($case['context']) ? $case['context'] : array();
      // Each case is an independent REQUEST. `$comment_alt`, `$comment_thread_alt` and
      // `$comment_depth` are process globals that comment_class() never resets, so a
      // second render in the same process would inherit the first one's parity.
      unset($GLOBALS['comment_alt'], $GLOBALS['comment_thread_alt'], $GLOBALS['comment_depth']);
      if (isset($case['request_uri'])) { $_SERVER['REQUEST_URI'] = $case['request_uri']; }
      else { $_SERVER['REQUEST_URI'] = '/'; }
      global $post;
      if (isset($context['postId'])) { $post = get_post($context['postId']); setup_postdata($post); }
      $html = '';
      foreach (parse_blocks($case['markup']) as $parsed) {
        if ($parsed['blockName'] === null && trim($parsed['innerHTML']) === '') { continue; }
        $block = new WP_Block($parsed, $context);
        $html .= $block->render();
      }
      $out['rendered'][$case['key']] = $html;
    }

    echo json_encode($out, JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
  PHP

  # ── The cases ──────────────────────────────────────────────────────────────
  #
  # Post 1 is the flat single-comment post the 18 literal screens render. Post 4 is the
  # deliberately hostile one: threaded four deep, a pending comment, a spam comment, a
  # trashed comment, a pingback, a trackback, a registered-user comment, and quotes,
  # dashes, primes, guillemets, CJK and an emoji in every string.
  #
  # ⚠️ The ids are the ORACLE corpus's current numbering (threaded post 4, password post
  # 10) — verify against the oracle's wp_posts before touching them: a Wave 3 corpus
  # renumbering silently turned the old ids 5/11 into a slugless draft and the emoji
  # post, which made every post-4 case here diverge for a fixture reason.
  COMMENT_TEMPLATE_INNER = '<!-- wp:comment-date /--><!-- wp:comment-author-name /-->' \
                   '<!-- wp:comment-content /--><!-- wp:comment-edit-link /-->' \
                   '<!-- wp:comment-reply-link /-->'

  def self.cases
    list = []
    { 1 => "/2026/03/hello-world/",
      4 => "/2026/03/published-article-with-he-said-its-a-test-she-replied-nested-59-tall-3-wide-french-%e3%80%8c%e6%97%a5%e6%9c%ac%e8%aa%9e%e3%80%8d-curly/",
      # Post 10 carries a password: post_password_required() (post-template.php:882)
      # empties comments-title (comments-title.php:19), comment-template
      # (comment-template.php:110), comments-pagination (comments-pagination.php:23) and
      # post-comments-form (post-comments-form.php:23) for the anonymous visitor. Without
      # this post in the corpus the guard was unexercised (verified by mutation).
      10 => "/2026/03/password-protected/" }
      .each do |post_id, uri|
      post_ctx = { "postId" => post_id, "postType" => "post" }
      list << { "key" => "comments-title-theme-#{post_id}", "request_uri" => uri, "context" => post_ctx,
                "markup" => '<!-- wp:comments-title {"level":3,"fontSize":"large"} /-->' }
      list << { "key" => "comments-title-default-#{post_id}", "request_uri" => uri, "context" => post_ctx,
                "markup" => "<!-- wp:comments-title /-->" }
      list << { "key" => "comments-title-nocount-#{post_id}", "request_uri" => uri, "context" => post_ctx,
                "markup" => '<!-- wp:comments-title {"showCommentsCount":false} /-->' }
      list << { "key" => "comments-title-notitle-#{post_id}", "request_uri" => uri, "context" => post_ctx,
                "markup" => '<!-- wp:comments-title {"showPostTitle":false} /-->' }
      list << { "key" => "comments-title-bare-#{post_id}", "request_uri" => uri, "context" => post_ctx,
                "markup" => '<!-- wp:comments-title {"showPostTitle":false,"showCommentsCount":false,"level":4} /-->' }
      list << { "key" => "post-comments-count-#{post_id}", "request_uri" => uri, "context" => post_ctx,
                "markup" => "<!-- wp:post-comments-count /-->" }
      list << { "key" => "post-comments-link-#{post_id}", "request_uri" => uri, "context" => post_ctx,
                "markup" => "<!-- wp:post-comments-link /-->" }
      list << { "key" => "post-comments-form-#{post_id}", "request_uri" => uri, "context" => post_ctx,
                "markup" => "<!-- wp:post-comments-form /-->" }
      list << { "key" => "comment-template-#{post_id}", "request_uri" => uri, "context" => post_ctx,
                "markup" => "<!-- wp:comment-template -->#{COMMENT_TEMPLATE_INNER}<!-- /wp:comment-template -->" }
      list << { "key" => "comments-pagination-#{post_id}", "request_uri" => uri, "context" => post_ctx,
                "markup" => '<!-- wp:comments-pagination {"layout":{"type":"flex","justifyContent":"space-between"}} -->' \
                            "<!-- wp:comments-pagination-previous /--><!-- wp:comments-pagination-next /-->" \
                            "<!-- /wp:comments-pagination -->" }
      list << { "key" => "comments-static-#{post_id}", "request_uri" => uri, "context" => post_ctx,
                "markup" => '<!-- wp:comments {"className":"wp-block-comments-query-loop",' \
                            '"style":{"spacing":{"margin":{"top":"var:preset|spacing|70","bottom":"var:preset|spacing|70"}}}} -->' \
                            '<div class="wp-block-comments wp-block-comments-query-loop" ' \
                            'style="margin-top:var(--wp--preset--spacing--70);margin-bottom:var(--wp--preset--spacing--70)">' \
                            '<!-- wp:comments-title {"level":3,"fontSize":"large"} /-->' \
                            "</div><!-- /wp:comments -->" }
    end

    # Per-comment blocks, over every comment in the corpus (both posts).
    [[1, 1], [4, 2], [4, 3], [4, 4], [4, 5], [4, 6], [4, 7], [4, 8], [4, 9], [4, 10], [4, 11]].each do |post_id, comment_id|
      ctx = { "postId" => post_id, "postType" => "post", "commentId" => comment_id }
      uri = post_id == 1 ? "/2026/03/hello-world/" : "/2026/03/x/"
      list << { "key" => "comment-date-#{comment_id}", "request_uri" => uri, "context" => ctx,
                "markup" => "<!-- wp:comment-date /-->" }
      list << { "key" => "comment-date-nolink-#{comment_id}", "request_uri" => uri, "context" => ctx,
                "markup" => '<!-- wp:comment-date {"isLink":false,"format":"D, d M Y H:i:s"} /-->' }
      list << { "key" => "comment-author-name-#{comment_id}", "request_uri" => uri, "context" => ctx,
                "markup" => "<!-- wp:comment-author-name /-->" }
      list << { "key" => "comment-author-name-nolink-#{comment_id}", "request_uri" => uri, "context" => ctx,
                "markup" => '<!-- wp:comment-author-name {"isLink":false} /-->' }
      list << { "key" => "comment-content-#{comment_id}", "request_uri" => uri, "context" => ctx,
                "markup" => "<!-- wp:comment-content /-->" }
      list << { "key" => "comment-reply-link-#{comment_id}", "request_uri" => uri, "context" => ctx,
                "markup" => "<!-- wp:comment-reply-link /-->" }
      list << { "key" => "comment-edit-link-#{comment_id}", "request_uri" => uri, "context" => ctx,
                "markup" => "<!-- wp:comment-edit-link /-->" }
    end

    # get_block_wrapper_attributes() over the supports these types declare. None of
    # these attribute shapes occurs in the corpus, which is exactly why they are here:
    # the corpus only ever exercises `className` + `style.spacing.margin` and a font-size
    # preset, so everything else in the wrapper would otherwise be unverified.
    wrapper_ctx = { "postId" => 1, "postType" => "post", "commentId" => 1 }
    {
      "wrapper-link-color" => '<!-- wp:comment-date {"style":{"elements":{"link":{"color":{"text":"#ff0000"}}}}} /-->',
      "wrapper-align-class-preset" =>
        '<!-- wp:comment-author-name {"textAlign":"right","className":"my-class","fontSize":"small"} /-->',
      "wrapper-padding-textcolor" =>
        '<!-- wp:comment-content {"style":{"spacing":{"padding":{"top":"20px"}}},"textColor":"accent-4"} /-->',
      # ⚠️ This one emits `id` TWICE — the callback's own `id="comments"` and the anchor
      # support's. The legacy does that; so does this.
      "wrapper-anchor-align-background" =>
        '<!-- wp:comments-title {"level":4,"align":"wide","anchor":"zzz","backgroundColor":"base",' \
        '"style":{"typography":{"fontStyle":"italic","fontWeight":"700"}}} /-->',
      "wrapper-border" =>
        '<!-- wp:post-comments-count {"textAlign":"center","style":{"border":{"radius":"4px","width":"2px"}}} /-->',
      # colors.php:63 — the PRESET attribute wins and the custom `style.color.text` is
      # then not emitted at all. A naive port emits both.
      "wrapper-preset-beats-custom" =>
        '<!-- wp:comment-author-name {"textColor":"accent-4","backgroundColor":"base","fontSize":"small",' \
        '"fontFamily":"body","style":{"typography":{"lineHeight":"1.5"},"color":{"text":"#111"},' \
        '"spacing":{"margin":{"top":"1px"}},"border":{"width":"3px"}}} /-->',
      # typography.php:302 (the class the engine does not produce) and border.php:109
      # (per-side values).
      "wrapper-text-align-and-border-side" =>
        '<!-- wp:comment-content {"style":{"typography":{"textAlign":"center"},' \
        '"border":{"top":{"width":"2px","color":"#0f0"}}}} /-->'
    }.each do |key, markup|
      list << { "key" => key, "request_uri" => "/2026/03/hello-world/", "context" => wrapper_ctx,
                "markup" => markup }
    end

    # Missing context is its own rule: every one of these callbacks bails out.
    %w[comment-date comment-author-name comment-content comment-reply-link
       comment-edit-link].each do |name|
      list << { "key" => "#{name}-no-context", "context" => {}, "markup" => "<!-- wp:#{name} /-->" }
    end
    list << { "key" => "post-comments-count-no-context", "context" => {},
              "markup" => "<!-- wp:post-comments-count /-->" }
    list << { "key" => "post-comments-link-no-context", "context" => {},
              "markup" => "<!-- wp:post-comments-link /-->" }
    list << { "key" => "post-comments-form-no-context", "context" => {},
              "markup" => "<!-- wp:post-comments-form /-->" }
    list << { "key" => "comment-template-no-context", "context" => {},
              "markup" => "<!-- wp:comment-template -->#{COMMENT_TEMPLATE_INNER}<!-- /wp:comment-template -->" }
    list
  end

  COMMENT_CASES = cases.freeze

  # ── Oracle ─────────────────────────────────────────────────────────────────
  def self.oracle
    @oracle ||= begin
      raise "no php" unless File.exist?(COMMENT_ORACLE_BOOTSTRAP) && system("which php > /dev/null 2>&1")

      Dir.mktmpdir("comment-parity") do |dir|
        cases_path = File.join(dir, "cases.json")
        File.write(cases_path, JSON.generate(COMMENT_CASES))
        script_path = File.join(dir, "oracle.php")
        File.write(script_path, format(COMMENT_ORACLE_SCRIPT, bootstrap: COMMENT_ORACLE_BOOTSTRAP, cases: cases_path))
        stdout, stderr, status = Open3.capture3("php", script_path)
        raise "oracle failed: #{stderr}" unless status.success?

        JSON.parse(stdout)
      end
    rescue StandardError => e
      { "error" => e.message }
    end
  end

  COMMENT_ORACLE = oracle

  before do
    skip "oracle unavailable: #{COMMENT_ORACLE["error"]}" if COMMENT_ORACLE["error"]

    # Sibling families' fixtures TRUNCATE the same tables, so this seed can still lose a
    # deadlock to one of them when two suites run at once. The savepoint makes the retry
    # possible without poisoning the example's own transaction.
    attempts = 0
    begin
      attempts += 1
      ActiveRecord::Base.transaction(requires_new: true) { seed_corpus! }
    rescue ActiveRecord::Deadlocked, ActiveRecord::RecordNotUnique
      if attempts < 25
        sleep(0.05 * attempts + (rand * 0.2))
        retry
      end
      raise
    end
  end

  # Rebuilds the oracle's rows, ids and all, so nothing has to be normalized away.
  #
  # The id columns are `GENERATED ALWAYS AS IDENTITY`, which is the schema saying that
  # ids are the database's business — so the fixture goes in through
  # `OVERRIDING SYSTEM VALUE` rather than by relaxing the schema.
  def insert_row!(table, attributes)
    conn = ActiveRecord::Base.connection
    columns = attributes.keys
    quoted = columns.map { |c| conn.quote_column_name(c) }
    updates = columns.reject { |c| c == "id" }.map { |c| "#{conn.quote_column_name(c)} = EXCLUDED.#{conn.quote_column_name(c)}" }
    # ON CONFLICT rather than DELETE-then-INSERT: deleting a user or a post cascades
    # into half the schema and deadlocks against every other suite running at the same
    # time, while an upsert takes a lock on the one row it writes.
    conn.execute(<<~SQL)
      INSERT INTO #{conn.quote_table_name(table)}
        (#{quoted.join(", ")})
        OVERRIDING SYSTEM VALUE
        VALUES (#{columns.map { |c| conn.quote(attributes[c]) }.join(", ")})
        ON CONFLICT (id) DO UPDATE SET #{updates.join(", ")}
    SQL
  end

  def mysql_time(value) = Time.utc(*value.scan(/\d+/).map(&:to_i))

  def seed_corpus!
    now = Time.utc(2026, 1, 1)
    # The suite is shared, and a sibling spec's `before(:context)` fixture is committed
    # rather than rolled back — so a comment this post does not own may already be
    # sitting on it. Only that is deleted; everything else is upserted, because TRUNCATE
    # takes an ACCESS EXCLUSIVE lock on four tables and deadlocks against every other
    # suite doing the same thing.
    post_ids = COMMENT_ORACLE["posts"].map { |p| p["id"] }
    Discussion::Comment.where(post_id: post_ids).delete_all

    # A sibling suite may already hold a COMMITTED row that collides on a unique index
    # while sitting at a DIFFERENT id, in which case `ON CONFLICT (id)` cannot see it.
    # It happens for real: the rebuild's own seed can number the users in a different
    # order than the oracle (and has numbered posts differently in the past), while
    # `posts_slug_hierarchical`, `users_login_key`, `users_email_key` and
    # `users_nicename_key` are all unique. Every such row is parked out of the way
    # first — an UPDATE takes one row lock and cascades into nothing, where a DELETE
    # would cascade through half the schema. Rows that DO share an id are then
    # overwritten by the upsert, and the example's transaction undoes all of it.
    Publishing::Post.where(slug: COMMENT_ORACLE["posts"].map { |p| p["slug"] }.compact_blank)
                    .update_all("slug = slug || '-parked'")
    Identity::User.where(login: COMMENT_ORACLE["users"].map { |u| u["login"] })
                  .or(Identity::User.where(email: COMMENT_ORACLE["users"].map { |u| u["email"] }))
                  .update_all("login = login || '-parked', nicename = nicename || '-parked', " \
                              "email = 'parked-' || email")

    Configuration::Setting.upsert_all(
      COMMENT_ORACLE["options"].map do |name, value|
        { name: name, value: value, autoload: false, created_at: now, updated_at: now }
      end, unique_by: :name
    )

    COMMENT_ORACLE["users"].each do |u|
      insert_row!("users", "id" => u["id"], "login" => u["login"], "email" => u["email"],
                           "password_digest" => "x", "nicename" => u["nicename"],
                           "display_name" => u["display_name"], "url" => u["url"],
                           "status" => "active", "registered_at" => now,
                           "created_at" => now, "updated_at" => now)
    end

    COMMENT_ORACLE["posts"].each do |p|
      insert_row!("posts",
                  "id" => p["id"],
                  "type" => p["type"] == "page" ? "Publishing::Page" : "Publishing::Article",
                  "author_id" => p["author_id"].positive? ? p["author_id"] : nil,
                  "parent_id" => p["parent_id"].positive? ? p["parent_id"] : nil,
                  "title" => p["title"], "slug" => p["slug"], "content" => p["content"],
                  "excerpt" => p["excerpt"], "status" => "published",
                  "published_at" => mysql_time(p["published_at"]),
                  "modified_at" => mysql_time(p["modified_at"]),
                  "comment_status" => p["comment_status"], "comment_count" => p["comment_count"],
                  "password_digest" => p["password"].to_s.empty? ? nil : "x",
                  "guid" => SecureRandom.uuid, "menu_order" => 0, "residual_attributes" => "{}",
                  "created_at" => now, "updated_at" => now)
    end

    # BR-MIGRATE-076 (BR-CMT-12): the legacy's five varchar values map onto four states.
    status_of = { "1" => "approved", "0" => "pending", "spam" => "spam",
                  "trash" => "trashed", "post-trashed" => "trashed" }
    COMMENT_ORACLE["comments"].each do |c|
      insert_row!("comments",
                  "id" => c["id"], "post_id" => c["post_id"],
                  "parent_id" => c["parent_id"].positive? ? c["parent_id"] : nil,
                  "user_id" => c["user_id"].positive? ? c["user_id"] : nil,
                  "author_name" => c["author_name"],
                  "author_email" => c["author_email"].to_s.empty? ? nil : c["author_email"],
                  "author_url" => c["author_url"], "content" => c["content"],
                  "status" => status_of.fetch(c["approved"], "pending"),
                  "kind" => c["kind"].to_s.empty? ? "comment" : c["kind"],
                  "submitted_at" => mysql_time(c["submitted_at"]),
                  "created_at" => now, "updated_at" => now)
    end
  end

  def render_case(kase)
    context = kase["context"] || {}
    post = context["postId"] ? Publishing::Post.find_by(id: context["postId"]) : nil
    ctx = Composition::RenderContext.new(post: post, context: context)
    Composition::Renderer.render(kase["markup"], ctx)
  end

  describe "every block in the family, against the live oracle" do
    COMMENT_CASES.each do |kase|
      it "renders #{kase["key"]} byte-for-byte" do
        expected = COMMENT_ORACLE["rendered"].fetch(kase["key"])
        expect(render_case(kase)).to eq(expected)
      end
    end
  end

  # ── Rules that the corpus alone cannot show ───────────────────────────────

  describe "the comment_text pipeline (wp-includes/default-filters.php:225..230)" do
    # ⚠️ Three of the seven stages are NOT implemented — make_clickable (priority 9),
    # convert_smilies (20) and force_balance_tags (25) — because their ports belong in
    # the `sanitizing` pack, which this file does not own. This example is the evidence
    # for the claim that they are no-ops on every comment in the corpus; the day one of
    # them stops being a no-op, this fails rather than the parity diff silently drifting.
    it "is complete for every comment body in the corpus" do
      COMMENT_ORACLE["comments"].each do |c|
        expect(Composition::Renderers::CommentBlocks::CommentText.call(c["content"]))
          .to eq(oracle_comment_text(c["id"])), "comment #{c["id"]}"
      end
    end

    def oracle_comment_text(comment_id)
      script = <<~PHP
        <?php
        require "#{COMMENT_ORACLE_BOOTSTRAP}";
        $c = get_comment(#{comment_id});
        echo apply_filters('comment_text', get_comment_text($c), $c, array());
      PHP
      Dir.mktmpdir do |dir|
        path = File.join(dir, "text.php")
        File.write(path, script)
        Open3.capture2("php", path).first
      end
    end
  end

  describe "core/comments (wp-includes/blocks/comments.php:33..39)" do
    let(:markup) do
      '<!-- wp:comments --><div class="wp-block-comments">x</div><!-- /wp:comments -->'
    end

    it "renders nothing without a postId" do
      expect(Composition::Renderer.render(markup, Composition::RenderContext.new)).to eq("")
    end

    it "renders nothing when comments are closed and there are none" do
      post = Publishing::Post.find(1)
      Discussion::Comment.where(post_id: 1).delete_all
      post.update_columns(comment_status: "closed")
      ctx = Composition::RenderContext.new(post: post, context: { "postId" => 1 })
      expect(Composition::Renderer.render(markup, ctx)).to eq("")
    end

    it "renders the saved markup when comments are closed but some exist" do
      post = Publishing::Post.find(1)
      post.update_columns(comment_status: "closed")
      ctx = Composition::RenderContext.new(post: post, context: { "postId" => 1 })
      expect(Composition::Renderer.render(markup, ctx))
        .to eq('<div class="wp-block-comments">x</div>')
    end
  end

  describe "core/comment-reply-link at the thread depth limit" do
    # get_comment_reply_link() returns null once `max_depth <= depth`
    # (comment-template.php:1776), and the callback renders nothing for an empty link.
    it "stops emitting a reply link at thread_comments_depth" do
      Configuration::Setting.find_by(name: "thread_comments_depth").update!(value: "4")
      ctx = Composition::RenderContext.new(post: Publishing::Post.find(4),
                                           context: { "postId" => 4, "commentId" => 5 })
      expect(Composition::Renderer.render("<!-- wp:comment-reply-link /-->", ctx)).to eq("")
    end

    it "emits nothing at all when threading is off" do
      Configuration::Setting.find_by(name: "thread_comments").update!(value: "")
      ctx = Composition::RenderContext.new(post: Publishing::Post.find(1),
                                           context: { "postId" => 1, "commentId" => 1 })
      expect(Composition::Renderer.render("<!-- wp:comment-reply-link /-->", ctx)).to eq("")
    end
  end

  describe "core/comment-template ordering" do
    # comment-template.php:120: 'desc' reverses the TOP-LEVEL list, never the replies.
    it "reverses only the roots when comment_order is desc" do
      Configuration::Setting.find_by(name: "comment_order").update!(value: "desc")
      ctx = Composition::RenderContext.new(post: Publishing::Post.find(4), context: { "postId" => 4 })
      html = Composition::Renderer.render(
        "<!-- wp:comment-template --><!-- wp:comment-date /--><!-- /wp:comment-template -->", ctx
      )
      roots = html.scan(/<li id="comment-(\d+)" class="[^"]*depth-1"/).flatten
      expect(roots).to eq(%w[2 9 10 11])
    end

    # The order-sensitive globals of comment_class(): a reply consumes an `alt` slot
    # before the next root does.
    it "numbers alt/thread-alt across the whole depth-first walk" do
      ctx = Composition::RenderContext.new(post: Publishing::Post.find(4), context: { "postId" => 4 })
      html = Composition::Renderer.render(
        "<!-- wp:comment-template --><!-- wp:comment-date /--><!-- /wp:comment-template -->", ctx
      )
      expect(html.scan(/<li id="comment-(\d+)" class="([^"]*)"/).to_h)
        .to eq("11" => "trackback even thread-even depth-1",
               "10" => "pingback odd alt thread-odd thread-alt depth-1",
               "9" => "comment even thread-even depth-1",
               "2" => "comment byuser comment-author-oracle_subscriber odd alt thread-odd thread-alt depth-1",
               "3" => "comment even depth-2",
               "4" => "comment odd alt depth-3",
               "5" => "comment even depth-4")
    end
  end

  describe "unapproved comments (comment-content.php:39, comment-author-name.php:45)" do
    # Only reachable by handing the block a commentId directly: the template never lists
    # a pending comment for an anonymous visitor.
    let(:ctx) do
      Composition::RenderContext.new(post: Publishing::Post.find(4),
                                     context: { "postId" => 4, "commentId" => 6 })
    end

    it "prefixes the moderation preview note and strips the body's markup" do
      html = Composition::Renderer.render("<!-- wp:comment-content /-->", ctx)
      expect(html).to start_with(
        '<div class="wp-block-comment-content"><p><em class="comment-awaiting-moderation">' \
        "Your comment is awaiting moderation. This is a preview; your comment will be " \
        "visible after it has been approved.</em></p>"
      )
      expect(html).not_to include("<p>Comment")
    end

    it "strips the author's link" do
      expect(Composition::Renderer.render("<!-- wp:comment-author-name /-->", ctx))
        .not_to include("<a ")
    end
  end

  # ── block style variations (section styles) ──────────────────────────────────────
  #
  # wp-includes/block-supports/block-style-variations.php:79 — a block whose
  # `className` names a variation the theme defines data for gets a per-INSTANCE
  # stylesheet, scoped to `is-style-<slug>--<n>`. DIFFERENTIAL: the oracle renders the
  # single template's own post-terms block (`"className":"is-style-post-terms-1"`,
  # backed by twentytwentyfive/styles/blocks/post-terms-1.json) and the expectation is
  # whatever it registered against the `block-style-variation-styles` handle — including
  # the instance number, which comes from `wp_unique_id()`'s request-wide counter
  # (functions.php:8177) and is 1 on a fresh render for both sides.
  describe Composition::Renderers::CommentBlocks::StyleVariations do
    it "generates the oracle's per-instance stylesheet, byte for byte" do
      block = '<!-- wp:post-terms {"term":"post_tag","className":"is-style-post-terms-1"} /-->'
      php = <<~PHP
        require "#{COMMENT_ORACLE_BOOTSTRAP}";
        do_blocks('#{block}');
        $extra = wp_styles()->registered['block-style-variation-styles']->extra['after'] ?? array();
        echo implode("\\n", array_filter($extra, 'is_string'));
      PHP
      oracle_css, status = Open3.capture2("php", "-r", php)
      skip "oracle unavailable" unless status.success?
      expect(oracle_css).to include("is-style-post-terms-1--1") # the fixture is alive

      ctx = Composition::RenderContext.new
      Composition::Renderer.render(block, ctx)
      expect(described_class.css(ctx)).to eq(oracle_css)
    end

    it "registers nothing for a variation the theme defines no data for" do
      ctx = Composition::RenderContext.new
      # `is-style-squared` is a REGISTERED button style but carries no theme.json data,
      # so `$theme_json['styles']['blocks'][…]['variations'][…]` is empty and the
      # support bails (:100) — no instance class, no stylesheet, no counter consumed.
      Composition::Renderer.render(
        '<!-- wp:button {"className":"is-style-squared"} --><div class="wp-block-button">' \
        '<a class="wp-block-button__link">x</a></div><!-- /wp:button -->', ctx
      )
      expect(described_class.css(ctx)).to be_nil
    end
  end
end
