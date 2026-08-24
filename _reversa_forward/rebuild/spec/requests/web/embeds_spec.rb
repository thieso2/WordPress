# frozen_string_literal: true

require "rails_helper"
require_relative "../../models/presentation/oracle"
require_relative "../../parity/harness/normalizer"
require_relative "../../parity/harness/oracle_client"

# web.embed beyond the corpus request. golden-web-embed.html covers ONE post's `/embed/`
# (Presentation::EmbedPage's spec compares it byte for byte); the `embed` endpoint is
# also registered with EP_PAGES (class-wp-rewrite.php:892, :1100), so every page URL has
# an embed variant the golden never exercises — the `type-page` post classes, the page
# body classes (page-template-*, page-parent, page-child, privacy-policy), a page's
# permalink in the share dialog, an empty excerpt, a trimmed one.
#
# DIFFERENTIAL: the pages are read from the oracle's database and the expectation is the
# oracle's own rendered `/<path>/embed/`, normalized by the same Parity::Normalizer the
# harness uses. Nothing here is a paraphrase of theme-compat/embed-content.php.
RSpec.describe "Web::EmbedsController", type: :request do
  EMBED_ORACLE = Presentation::SpecOracle
  EMBED_HTTP = Parity::OracleClient.new
  EMBED_PAGES = EMBED_ORACLE.available? ? EMBED_ORACLE.run(<<~PHP) : nil
    $out = array('options' => array(), 'pages' => array());
    foreach (array('blogname', 'wp_page_for_privacy_policy', 'show_on_front', 'page_on_front',
                   'page_for_posts') as $o) {
      $out['options'][$o] = get_option($o);
    }
    foreach (get_pages(array('post_status' => 'publish,private', 'sort_column' => 'ID')) as $p) {
      $out['pages'][] = array(
        'id' => (int) $p->ID, 'slug' => $p->post_name, 'title' => $p->post_title,
        'content' => $p->post_content, 'excerpt' => $p->post_excerpt,
        'parent' => (int) $p->post_parent, 'status' => $p->post_status,
        'date' => $p->post_date_gmt, 'template' => get_page_template_slug($p->ID),
        'comment_status' => $p->comment_status, 'comment_count' => (int) $p->comment_count,
        'menu_order' => (int) $p->menu_order, 'path' => get_page_uri($p),
      );
    }
    echo json_encode($out, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
  PHP

  # The request host must be one the normalizer maps to <SITE> (normalizer.rb:131), and
  # `home` must agree with it — `Site.home_url` prints it in every self-link.
  EMBED_HOST = "127.0.0.1:3100"

  before do
    skip "the PHP oracle is not available" if EMBED_PAGES.nil?

    host! EMBED_HOST
    Configuration::Setting.find_or_initialize_by(name: "home").update!(value: "http://#{EMBED_HOST}")
    Configuration::Setting.find_or_initialize_by(name: "blogname")
                          .update!(value: EMBED_PAGES["options"]["blogname"])
    # `is_privacy_policy()` (query.php:214) gives the `privacy-policy` body class;
    # show_on_front / page_on_front / page_for_posts decide is_front_page() and are read
    # by the page-list block the 404 screen's navigation renders (navigation_blocks.rb:1459
    # — which, like `(int) get_option()`, needs the row to exist).
    %w[wp_page_for_privacy_policy show_on_front page_on_front page_for_posts].each do |name|
      Configuration::Setting.find_or_initialize_by(name: name)
                            .update!(value: EMBED_PAGES["options"][name].to_s)
    end
    EMBED_PAGES["pages"].sort_by { |p| p["id"] }.each { |page| insert_page!(page) }
  end

  def author
    @author ||= Identity::User.create!(login: "oracle_admin", nicename: "oracle_admin",
                                       display_name: "oracle_admin", email: "oracle_admin@example.test",
                                       password_digest: "x", registered_at: Time.current)
  end

  STATUS = { "publish" => "published", "private" => "private" }.freeze

  # ⚠️ The oracle's ids, on purpose. `print_embed_sharing_dialog()` builds its ids from
  # `get_the_ID() . '-' . wp_rand()` (embed.php:1204) and the normalizer masks only the
  # wp_rand() half; `parent-pageid-N` (post-template.php:728) is not masked at all.
  # posts.id is GENERATED ALWAYS (AD-05), hence OVERRIDING SYSTEM VALUE — the same helper
  # shape as spec/models/presentation/embed_page_spec.rb.
  def insert_page!(page)
    attributes = {
      "id" => page["id"], "type" => "Publishing::Page", "author_id" => author.id,
      "parent_id" => page["parent"].zero? ? nil : page["parent"],
      "title" => page["title"], "slug" => page["slug"], "content" => page["content"],
      "excerpt" => page["excerpt"], "status" => STATUS.fetch(page["status"]),
      "published_at" => Time.find_zone!("UTC").parse(page["date"]),
      "comment_status" => page["comment_status"], "comment_count" => page["comment_count"],
      "menu_order" => page["menu_order"], "template_slug" => page["template"].to_s,
      "guid" => SecureRandom.uuid,
    }
    conn = ActiveRecord::Base.connection
    conn.execute(<<~SQL)
      INSERT INTO posts (#{attributes.keys.map { |c| conn.quote_column_name(c) }.join(", ")})
        OVERRIDING SYSTEM VALUE
        VALUES (#{attributes.values.map { |v| conn.quote(v) }.join(", ")})
    SQL
  end

  def normalized(body, content_type)
    Parity::Normalizer.new.call(body, content_type: content_type).lines.map(&:chomp)
  end

  it "renders every page's /embed/ as the oracle does, byte for byte after normalization" do
    paths = EMBED_PAGES["pages"].map { |p| "/#{p["path"]}/embed/" }
    expect(paths).to include("/parent-page/child-page/embed/", "/privacy-policy/embed/")

    paths.each do |path|
      oracle = EMBED_HTTP.get(path)
      expect(oracle.status).to eq(200), "#{path}: the oracle answered #{oracle.status}"

      get path
      expect(response).to have_http_status(:ok), "#{path}: the rebuild answered #{response.status}"
      expect(response.headers["X-WP-embed"]).to eq("true")
      expect(normalized(response.body, response.content_type))
        .to eq(normalized(oracle.body, oracle.content_type)), "#{path} differs from the oracle"
    end
  end

  it "404s an unknown page path under /embed/" do
    get "/parent-page/no-such-child/embed/"
    expect(response).to have_http_status(:not_found)
  end
end
