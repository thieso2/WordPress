# frozen_string_literal: true

require "rails_helper"
require "net/http"
require "digest/md5"
require_relative "../../models/presentation/oracle"
require_relative "../../parity/harness/normalizer"
require_relative "../../parity/harness/oracle_client"

# `wp-comments-post.php` — DIFFERENTIAL against the live oracle.
#
# Two instruments, chosen by whether the probe writes:
#
#   * Every refusal (405, empty 200, the wp_die() pages: 200/403/409) is NON-MUTATING on
#     the oracle, so it is POSTed over HTTP to BOTH systems and the status, the headers
#     that matter and the body are compared — the body byte for byte for the wp_die page,
#     because nothing in it varies between the systems.
#
#   * A successful submission WRITES. RISK-002: the oracle's database is read-only to the
#     rebuild and the goldens depend on a reproducible corpus, so those cases exercise the
#     oracle's own wp_handle_comment_submission() in PHP inside `START TRANSACTION … ROLLBACK`:
#     the oracle's write path runs end to end, the resulting row is read back and compared
#     with the rebuild's, and nothing persists. The HTTP half of the success contract
#     (302, Location, X-Redirect-By, the three Set-Cookie lines) was observed once on the
#     live oracle with curl (the values are quoted where they are asserted) and the oracle
#     was reseeded afterwards.
#
# The corpus — posts, comments, settings, users — is read from the oracle and inserted
# WITH THE ORACLE'S IDS, so the same `comment_post_ID`/`comment_parent` payload means the
# same thing on both sides.
RSpec.describe "Web::CommentsController", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  CS_ORACLE = Presentation::SpecOracle
  CS_HTTP = Parity::OracleClient.new
  CS_HOST = "127.0.0.1:3100"
  CS_ENDPOINT = "/wp-comments-post.php"
  CS_AGENT = "reversa-parity-harness/1.0"

  CS_OPTIONS = %w[require_name_email comment_registration comment_moderation comment_previously_approved
                  comment_max_links moderation_keys disallowed_keys show_comments_cookies_opt_in
                  thread_comments thread_comments_depth page_comments comments_per_page
                  default_comments_page timezone_string gmt_offset permalink_structure blogname].freeze

  CS_CORPUS = CS_ORACLE.available? ? CS_ORACLE.run(<<~PHP, JSON.generate(options: CS_OPTIONS)) : nil
    global $wpdb;
    $in = json_decode(file_get_contents('php://stdin'), true);
    $out = array('options' => array(), 'posts' => array(), 'comments' => array(), 'users' => array());
    foreach ($in['options'] as $o) { $out['options'][$o] = get_option($o); }
    $out['options']['siteurl'] = get_option('siteurl');
    foreach ($wpdb->get_results("SELECT * FROM {$wpdb->posts} WHERE post_type IN ('post','page') ORDER BY ID", ARRAY_A) as $p) {
      $out['posts'][] = array(
        'id' => (int) $p['ID'], 'type' => $p['post_type'], 'status' => $p['post_status'],
        'slug' => $p['post_name'], 'title' => $p['post_title'], 'content' => $p['post_content'],
        'excerpt' => $p['post_excerpt'], 'parent' => (int) $p['post_parent'],
        'date_gmt' => $p['post_date_gmt'], 'comment_status' => $p['comment_status'],
        'password' => $p['post_password'], 'author' => (int) $p['post_author'],
      );
    }
    foreach ($wpdb->get_results("SELECT * FROM {$wpdb->comments} ORDER BY comment_ID", ARRAY_A) as $c) {
      $out['comments'][] = $c;
    }
    foreach (get_users(array('orderby' => 'ID')) as $u) {
      $out['users'][] = array('id' => (int) $u->ID, 'login' => $u->user_login, 'email' => $u->user_email,
                              'display_name' => $u->display_name, 'url' => $u->user_url,
                              'nicename' => $u->user_nicename, 'roles' => array_values($u->roles));
    }
    echo json_encode($out, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
  PHP

  CS_POST_STATUS = { "publish" => "published", "private" => "private", "draft" => "draft",
                     "pending" => "pending", "future" => "scheduled", "trash" => "trashed",
                     "auto-draft" => "auto_draft" }.freeze
  CS_COMMENT_STATUS = { "1" => "approved", "0" => "pending", "spam" => "spam", "trash" => "trashed" }.freeze

  before do
    skip "the PHP oracle is not available" if CS_CORPUS.nil?

    host! CS_HOST
    CS_CORPUS["options"].each { |name, value| Configuration::Setting.set(name, value.to_s) }
    # home/siteurl are the request host: the redirect and the cookie hash derive from
    # them, and the normalizer maps both hosts to <SITE>.
    Configuration::Setting.set("home", "http://#{CS_HOST}")
    Configuration::Setting.set("siteurl", "http://#{CS_HOST}")
    CS_CORPUS["users"].each { |u| insert_user!(u) }
    CS_CORPUS["posts"].sort_by { |p| p["id"] }.each { |p| insert_post!(p) }
    # ⚠️ Observed after `bin/oracle reseed`: the default comment (comment_ID 1) points at a
    # post_ID that no longer exists — the reseed re-creates `hello-world` under a new id.
    # An orphan cannot be inserted under the FK, and the oracle itself would answer
    # "comment_id_not_found" for it; it is left out and counted out.
    @seeded_comments = CS_CORPUS["comments"].select { |c| post_by_id(c["comment_post_ID"].to_i) }
    @seeded_comments.each { |c| insert_comment!(c) }
    # The identity sequences know nothing about the ids written past them.
    %w[users posts comments].each do |table|
      ActiveRecord::Base.connection.execute(
        "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), COALESCE((SELECT MAX(id) FROM #{table}), 1))"
      )
    end
    Discussion::RateLimit.delete_all
  end

  # ── corpus loading, with the oracle's ids (GENERATED ALWAYS → OVERRIDING SYSTEM VALUE) ──

  def insert_rows!(table, attributes)
    conn = ActiveRecord::Base.connection
    conn.execute(<<~SQL)
      INSERT INTO #{table} (#{attributes.keys.map { |c| conn.quote_column_name(c) }.join(", ")})
        OVERRIDING SYSTEM VALUE
        VALUES (#{attributes.values.map { |v| conn.quote(v) }.join(", ")})
    SQL
  end

  def insert_user!(u)
    insert_rows!("users", "id" => u["id"], "login" => u["login"], "email" => u["email"],
                          "password_digest" => "*disabled*", "nicename" => u["nicename"],
                          "display_name" => u["display_name"], "url" => u["url"],
                          "registered_at" => Time.current)
    u["roles"].each { |r| Identity::RoleAssignment.create!(user_id: u["id"], role: r) }
  end

  def insert_post!(p)
    status = CS_POST_STATUS.fetch(p["status"])
    date = p["date_gmt"].start_with?("0000") ? nil : Time.find_zone!("UTC").parse(p["date_gmt"])
    attributes = {
      "id" => p["id"], "type" => p["type"] == "page" ? "Publishing::Page" : "Publishing::Article",
      "author_id" => p["author"].zero? ? nil : p["author"],
      "parent_id" => p["parent"].zero? ? nil : p["parent"],
      "title" => p["title"], "slug" => p["slug"].presence, "content" => p["content"],
      "excerpt" => p["excerpt"], "status" => status, "published_at" => date,
      "comment_status" => p["comment_status"], "guid" => SecureRandom.uuid,
      "password_digest" => p["password"].presence && "x",
    }
    if status == "trashed"
      attributes["trashed_at"] = Time.current
      attributes["status_before_trash"] = "published"
    end
    insert_rows!("posts", attributes)
  end

  def insert_comment!(c)
    insert_rows!("comments",
                 "id" => c["comment_ID"].to_i, "post_id" => c["comment_post_ID"].to_i,
                 "parent_id" => c["comment_parent"].to_i.zero? ? nil : c["comment_parent"].to_i,
                 "user_id" => c["user_id"].to_i.zero? ? nil : c["user_id"].to_i,
                 "author_name" => c["comment_author"], "author_email" => c["comment_author_email"].presence,
                 "author_url" => c["comment_author_url"].presence, "author_ip" => c["comment_author_IP"].presence,
                 "user_agent" => c["comment_agent"].presence, "content" => c["comment_content"],
                 "status" => CS_COMMENT_STATUS.fetch(c["comment_approved"]), "kind" => c["comment_type"],
                 "submitted_at" => Time.find_zone!("UTC").parse(c["comment_date_gmt"]))
  end

  def post_by_slug(slug) = CS_CORPUS["posts"].find { |p| p["slug"] == slug }
  def post_by_id(id) = CS_CORPUS["posts"].find { |p| p["id"] == id }
  def hello_world_id = post_by_slug("hello-world")["id"]
  def seeded_count = @seeded_comments.length
  # ⚠️ Comment ids are NOT stable across `bin/oracle reseed` (InnoDB keeps its
  # auto-increment counter), so the corpus rows are found by what they ARE, never by id:
  # a probe that meant "reply to the pending comment" but carried a stale id once turned
  # into an admission and WROTE to the oracle.
  def corpus_comment(approved:, root: true, author: nil)
    CS_CORPUS["comments"].find do |c|
      c["comment_approved"] == approved && (!root || c["comment_parent"].to_i.zero?) &&
        (author.nil? || c["comment_author"].include?(author))
    end
  end

  def pending_comment = corpus_comment(approved: "0")
  def spam_comment = corpus_comment(approved: "spam")
  def quoted_root_comment = corpus_comment(approved: "1", author: "root-approved")

  # ── the two instruments ─────────────────────────────────────────────────────────

  # The oracle over HTTP. `local_host` picks the source address, which is the IP the
  # flood rule keys on (BR-MIGRATE-067) — the loopback /8 makes them free.
  def oracle_post(fields, local_host: nil)
    uri = URI.join(CS_HTTP.instance_variable_get(:@base), CS_ENDPOINT)
    opts = { open_timeout: 5, read_timeout: 30 }
    opts[:local_host] = local_host if local_host
    response = Net::HTTP.start(uri.host, uri.port, **opts) do |http|
      http.post(uri.path, URI.encode_www_form(fields),
                "Content-Type" => "application/x-www-form-urlencoded", "User-Agent" => CS_AGENT)
    end
    Parity::OracleClient::Response.new(status: response.code.to_i, body: response.body.to_s,
                                       content_type: response["content-type"].to_s, path: CS_ENDPOINT,
                                       location: response["location"])
      .tap { |r| r.define_singleton_method(:allow) { response["allow"] } }
  end

  def oracle_get
    uri = URI.join(CS_HTTP.instance_variable_get(:@base), CS_ENDPOINT)
    Net::HTTP.start(uri.host, uri.port) { |http| http.get(uri.path, "User-Agent" => CS_AGENT) }
  end

  # The oracle's own write path, in PHP, rolled back. Returns one result per case:
  # either `error` [code, message, status] or `comment` (the row as inserted), `status`
  # (wp_get_comment_status) and `location` (wp-comments-post.php:57-80, computed the
  # way the script computes it, through wp_sanitize_redirect/wp_validate_redirect).
  def oracle_submit(cases)
    CS_ORACLE.run(<<~PHP, JSON.generate(cases: cases))
      global $wpdb;
      $in = json_decode(file_get_contents('php://stdin'), true);
      $out = array();
      foreach ($in['cases'] as $case) {
        $wpdb->query('START TRANSACTION');
        $_SERVER['REMOTE_ADDR'] = $case['ip'];
        $_SERVER['HTTP_USER_AGENT'] = $case['agent'];
        $_SERVER['REQUEST_URI'] = '/wp-comments-post.php';
        foreach ((array) ($case['options'] ?? array()) as $name => $value) { update_option($name, $value); }
        // wp_set_current_user fires `set_current_user`, which re-runs kses_init().
        wp_set_current_user(empty($case['user']) ? 0 : get_user_by('login', $case['user'])->ID);
        $fields = $case['fields'];
        $r = wp_handle_comment_submission($fields);
        if (is_wp_error($r)) {
          $out[] = array('error' => array($r->get_error_code(), $r->get_error_message(), (int) $r->get_error_data()));
        } else {
          $row = $wpdb->get_row($wpdb->prepare("SELECT * FROM {$wpdb->comments} WHERE comment_ID = %d", $r->comment_ID), ARRAY_A);
          $consent = isset($fields['wp-comment-cookies-consent']);
          $location = empty($fields['redirect_to']) ? get_comment_link($r) : $fields['redirect_to'] . '#comment-' . $r->comment_ID;
          if (!$consent && 'unapproved' === wp_get_comment_status($r) && !empty($r->comment_author_email)) {
            $location = add_query_arg(array('unapproved' => $r->comment_ID, 'moderation-hash' => wp_hash($r->comment_date_gmt)), $location);
          }
          $location = wp_validate_redirect(wp_sanitize_redirect($location), admin_url());
          $out[] = array('comment' => $row, 'status' => wp_get_comment_status($r), 'location' => $location);
        }
        $wpdb->query('ROLLBACK');
        wp_cache_flush();
      }
      echo json_encode($out, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
    PHP
  end

  def rebuild_post(fields, ip: "203.0.113.10", agent: CS_AGENT)
    post CS_ENDPOINT, params: fields, headers: { "User-Agent" => agent }, env: { "REMOTE_ADDR" => ip }
  end

  def normalized(body, content_type = "text/html")
    Parity::Normalizer.new.call(body, content_type: content_type)
  end

  # Location values carry the new comment's id (sequences differ, stripAutoincrementIds)
  # and a per-installation HMAC; both are masked, the host is <SITE>.
  def normalized_location(location)
    location.to_s.sub(%r{https?://(?:127\.0\.0\.1|localhost)(?::\d+)?}, "<SITE>")
            .gsub(/comment-\d+/, "comment-<ID>").gsub(/unapproved=\d+/, "unapproved=<ID>")
            .gsub(/moderation-hash=[0-9a-f]+/, "moderation-hash=<HASH>")
  end

  # The comparable projection of a comment row, on both sides.
  def oracle_row(r)
    { author: r["comment_author"], email: r["comment_author_email"], url: r["comment_author_url"],
      ip: r["comment_author_IP"], agent: r["comment_agent"], content: r["comment_content"],
      status: CS_COMMENT_STATUS.fetch(r["comment_approved"]), parent: r["comment_parent"].to_i,
      type: r["comment_type"], user: r["user_id"].to_i.zero? ? nil : CS_CORPUS["users"].find { |u| u["id"] == r["user_id"].to_i }["login"] }
  end

  def rebuild_row(c)
    { author: c.author_name, email: c.author_email.to_s, url: c.author_url.to_s,
      ip: c.author_ip.to_s, agent: c.user_agent.to_s, content: c.content,
      status: c.status, parent: c.parent_id.to_i, type: c.kind, user: c.user&.login }
  end

  def valid(overrides = {})
    { "comment_post_ID" => hello_world_id, "author" => "Parity Commenter",
      "email" => "parity.commenter@example.com", "url" => "", "comment" => "A remark for the differential." }
      .merge(overrides)
  end

  CS_BACKSLASH = 'Windows path C:\\Users\\thies\\file.txt — regex \\d+\\s*\\\\ — literal \\n not a newline — LaTeX \\frac{1}{2} — escaped quote \\" and \\\''
  CS_QUOTES = "He said \"it's a test\" -- she replied '\"nested\"' ... 5'9\" tall, 3\" wide « French » 「日本語」 ‘curly’ “already curly”"
  CS_ASTRAL = "Emoji 😀🧬🚀 · Math 𝔘𝔫𝔦𝔠𝔬𝔡𝔢 𝕬𝖑𝖌𝖊𝖇𝖗𝖆 · CJK-Ext-B 𠜎𠜱𠝹 · ZWJ 👨‍👩‍👧‍👦 · Flag 🇯🇵"

  # ════════════════════════════════════════════════════════════════════════════════
  # 1. Refusals — live HTTP, both systems, nothing written on either side.
  # ════════════════════════════════════════════════════════════════════════════════

  it "answers anything but POST with 405, Allow: POST and an empty text/plain body (wp-comments-post.php:8-18)" do
    oracle = oracle_get
    get CS_ENDPOINT
    expect([oracle.code.to_i, oracle["allow"], oracle.body.to_s]).to eq([405, "POST", ""])
    expect(response).to have_http_status(:method_not_allowed)
    expect(response.headers["Allow"]).to eq("POST")
    expect(response.content_type).to start_with("text/plain")
    expect(response.body).to eq("")
  end

  it "renders the wp_die() page byte for byte (comments closed, 403)" do
    fields = valid("comment_post_ID" => post_by_slug("sample-page")["id"])
    oracle = oracle_post(fields)
    rebuild_post(fields)
    expect(oracle.status).to eq(403)
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to eq(oracle.body)
    expect(response.body).to include("<title>Comment Submission Failure</title>",
                                     "<p>Sorry, comments are closed for this item.</p>",
                                     "<p><a href='javascript:history.back()'>&laquo; Back</a></p>")
    expect(response.headers["Expires"]).to eq("Wed, 11 Jan 1984 05:00:00 GMT")
  end

  # Every WP_Error WITHOUT data: wp-comments-post.php:38 `exit` — 200 and nothing.
  {
    "no fields at all" => {},
    "a post that does not exist" => { "comment_post_ID" => 999_999 },
    "a trashed post" => { "slug" => "trashed-article" },
    "a draft" => { "slug" => nil, "status" => "draft" },
    "a private post, anonymously" => { "slug" => "private-article" },
    "a scheduled post" => { "slug" => "scheduled-for-the-future" },
    "a password-protected post" => { "slug" => "password-protected" },
  }.each do |label, spec|
    it "is silent (200, empty body) on #{label}" do
      fields =
        if spec.empty? then {}
        elsif spec.key?("status") then valid("comment_post_ID" => CS_CORPUS["posts"].find { |p| p["status"] == spec["status"] }["id"])
        elsif spec.key?("slug") then valid("comment_post_ID" => post_by_slug(spec["slug"])["id"])
        else valid(spec)
        end
      oracle = oracle_post(fields)
      rebuild_post(fields)
      expect(oracle.status).to eq(200)
      expect(oracle.body).to eq("")
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("")
      expect(Discussion::Comment.count).to eq(seeded_count)
    end
  end

  # Every WP_Error WITH data: the wp_die() page carries the legacy's LITERAL message.
  def self.refusal(label, status, message, &fields)
    it "refuses #{label} with #{status} and the literal message" do
      f = instance_exec(&fields)
      oracle = oracle_post(f)
      rebuild_post(f)
      expect(oracle.status).to eq(status)
      expect(oracle.body).to include("<p>#{message}</p>")
      expect(response.status).to eq(status)
      expect(normalized(response.body)).to eq(normalized(oracle.body))
      expect(response.body).to include(%(<div class="wp-die-message"><p>#{message}</p></div>))
      expect(Discussion::Comment.count).to eq(seeded_count)
    end
  end

  refusal("a missing name", 200, "<strong>Error:</strong> Please fill the required fields.") { valid.except("author") }
  refusal("a missing email", 200, "<strong>Error:</strong> Please fill the required fields.") { valid("email" => "") }
  refusal("an invalid email", 200, "<strong>Error:</strong> Please enter a valid email address.") { valid("email" => "not-an-email") }
  refusal("an empty comment", 200, "<strong>Error:</strong> Please type your comment text.") { valid("comment" => "   ") }
  refusal("a name over 245 bytes", 200, "<strong>Error:</strong> Your name is too long.") { valid("author" => "n" * 246) }
  refusal("an email over 100 bytes", 200, "<strong>Error:</strong> Your email address is too long.") { valid("email" => "#{"e" * 95}@ex.com") }
  refusal("a URL over 200 bytes", 200, "<strong>Error:</strong> Your URL is too long.") { valid("url" => "http://example.com/#{"u" * 190}") }
  refusal("a comment over 65525 bytes", 200, "<strong>Error:</strong> Your comment is too long.") { valid("comment" => "c" * 65_526) }
  refusal("a reply to a pending comment", 403, "Sorry, replies to unapproved comments are not allowed.") do
    pending = pending_comment
    valid("comment_post_ID" => pending["comment_post_ID"].to_i, "comment_parent" => pending["comment_ID"].to_i)
  end
  refusal("a reply to a spam comment", 403, "Sorry, replies to unapproved comments are not allowed.") do
    spam = spam_comment
    valid("comment_post_ID" => spam["comment_post_ID"].to_i, "comment_parent" => spam["comment_ID"].to_i)
  end
  refusal("a reply to a parent that does not exist", 403, "Sorry, replies to unapproved comments are not allowed.") do
    valid("comment_parent" => 999_999)
  end

  # BR-MIGRATE-065 (BR-CMT-01): the duplicate is HTTP 409, and the message keeps its
  # HTML entity.
  it "refuses a duplicate of an existing comment with 409 (BR-MIGRATE-065)" do
    original = quoted_root_comment
    fields = { "comment_post_ID" => original["comment_post_ID"].to_i, "author" => original["comment_author"],
               "email" => original["comment_author_email"], "comment" => original["comment_content"] }
    oracle = oracle_post(fields)
    rebuild_post(fields)
    expect(oracle.status).to eq(409)
    expect(response).to have_http_status(:conflict)
    expect(response.body).to eq(oracle.body)
    expect(response.body).to include("Duplicate comment detected; it looks as though you&#8217;ve already said that!")
  end

  # Over-length: 200, not 400 (BR-MIGRATE-075) — asserted above per field; here the
  # rule's own statement, on the status alone, so a future "fix" to 400 is caught by name.
  it "answers an over-length field with HTTP 200, not 400 (BR-MIGRATE-075)" do
    rebuild_post(valid("author" => "n" * 246))
    expect(response.status).to eq(200)
  end

  it "refuses an anonymous submission with 403 when comment_registration is on" do
    oracle = oracle_submit([{ fields: valid, ip: "203.0.113.90", agent: CS_AGENT,
                              options: { "comment_registration" => "1" } }]).first
    Configuration::Setting.set("comment_registration", "1")
    rebuild_post(valid)
    expect(oracle["error"]).to eq(["not_logged_in", "Sorry, you must be logged in to comment.", 403])
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include("<p>Sorry, you must be logged in to comment.</p>")
  end

  # ════════════════════════════════════════════════════════════════════════════════
  # 2. Admissions — the oracle's write path in a rolled-back transaction vs. the
  #    rebuild's real one. Row, verdict and redirect target are compared.
  # ════════════════════════════════════════════════════════════════════════════════

  def self.admission(label, ip:, &block)
    it "admits #{label} exactly as the oracle does" do
      fields = instance_exec(&block)
      expected = oracle_submit([{ fields: fields, ip: ip, agent: CS_AGENT }]).first
      expect(expected["error"]).to be_nil, "the oracle refused: #{expected["error"].inspect}"

      before = Discussion::Comment.count
      rebuild_post(fields, ip: ip)

      expect(response).to have_http_status(:found), "rebuild answered #{response.status}: #{response.body[0, 300]}"
      expect(response.headers["X-Redirect-By"]).to eq("WordPress")
      expect(normalized_location(response.location)).to eq(normalized_location(expected["location"]))
      expect(Discussion::Comment.count).to eq(before + 1)

      created = Discussion::Comment.order(:id).last
      expect(rebuild_row(created)).to eq(oracle_row(expected["comment"]))
      expect(created.moderation_verdicts.count).to eq(1)
      expect(created.moderation_verdicts.first.outcome).to eq(created.status)
      created
    end
  end

  # RISK-008 head-on: the backslash corpus, quotes, kses payload, a bare URL, a
  # schemeless website. comment_previously_approved is on and this author is new, so
  # the verdict is pending — with consent, no moderation arguments on the redirect.
  admission("a first-time author with cookie consent, backslash corpus included", ip: "203.0.113.21") do
    { "comment_post_ID" => hello_world_id, "author" => "Probe <b>One</b>", "email" => "probe.one@example.com",
      "url" => "example.com/probe", "wp-comment-cookies-consent" => "yes",
      "comment" => "#{CS_BACKSLASH}\n\n#{CS_QUOTES}\n<b>bold</b> <script>x</script> <a href=\"http://example.com/\">l</a> http://bare.example/x" }
  end

  # BR-MIGRATE-073 (BR-CMT-09): an author with an approved comment is approved again.
  # Both sides build the history inside the probe: the oracle approves the first
  # submission with wp_set_comment_status() before taking the second, all rolled back.
  it "admits a previously approved author with an immediate approval (BR-MIGRATE-073)" do
    first = valid("author" => "Returning Author", "email" => "returning@example.com", "comment" => "First visit.")
    second = valid("author" => "Returning Author", "email" => "returning@example.com",
                   "comment" => "A return visit. #{CS_ASTRAL}")
    expected = CS_ORACLE.run(<<~PHP, JSON.generate(first: first, second: second))
      global $wpdb;
      $in = json_decode(file_get_contents('php://stdin'), true);
      $wpdb->query('START TRANSACTION');
      $_SERVER['REMOTE_ADDR'] = '203.0.113.22'; $_SERVER['HTTP_USER_AGENT'] = 'reversa-parity-harness/1.0';
      $a = wp_handle_comment_submission($in['first']);
      wp_set_comment_status($a->comment_ID, 'approve');
      // BR-MIGRATE-067: the flood window also keys on the EMAIL, so the history is moved
      // back two hours — the same age the rebuild side gives its first comment.
      $ago = gmdate('Y-m-d H:i:s', time() - 7200);
      wp_update_comment(array('comment_ID' => $a->comment_ID, 'comment_date' => get_date_from_gmt($ago), 'comment_date_gmt' => $ago));
      $_SERVER['REMOTE_ADDR'] = '203.0.113.122';
      $b = wp_handle_comment_submission($in['second']);
      $row = is_wp_error($b) ? null : $wpdb->get_row($wpdb->prepare("SELECT * FROM {$wpdb->comments} WHERE comment_ID = %d", $b->comment_ID), ARRAY_A);
      $wpdb->query('ROLLBACK');
      echo json_encode(array('first_status' => is_wp_error($a) ? $a->get_error_code() : $a->comment_approved,
                             'second' => $row), JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
    PHP
    expect(expected["first_status"]).to eq("0")
    expect(expected["second"]["comment_approved"]).to eq("1")

    rebuild_post(first, ip: "203.0.113.22")
    expect(response).to have_http_status(:found)
    history = Discussion::Comment.order(:id).last
    history.update!(submitted_at: 2.hours.ago)
    history.approve!
    rebuild_post(second, ip: "203.0.113.122")
    expect(response).to have_http_status(:found)
    created = Discussion::Comment.order(:id).last
    expect(rebuild_row(created)).to eq(oracle_row(expected["second"]))
    expect(created.status).to eq("approved")
  end

  # ⚠️ FINDING (RISK-008, in the LEGACY). check_comment() (comment.php:91-110) runs the
  # previously-approved lookup with the SLASHED author name — wp_new_comment() receives
  # wp_slash()ed data and never unslashes before `$wpdb->prepare(... comment_author = %s)`
  # — so an author whose name carries a quote or an apostrophe never matches their own
  # approved history: `Commenter "root-approved" O'Brien 😀` is held as pending by the
  # oracle on every return visit. Rails params are never slashed (non-negotiable 5), the
  # rebuild compares the stored name to itself, and approves. Recorded here as the
  # divergence it is; the direction is the one BR-MIGRATE-073 states.
  it "approves a returning author whose name carries quotes, where the legacy's slashed lookup misses (finding)" do
    prior = quoted_root_comment
    expect(prior["comment_author"]).to include('"', "'")
    fields = { "comment_post_ID" => hello_world_id, "author" => prior["comment_author"],
               "email" => prior["comment_author_email"], "comment" => "A return visit with quotes in my name." }
    expected = oracle_submit([{ fields: fields, ip: "203.0.113.23", agent: CS_AGENT }]).first
    expect(expected["comment"]["comment_approved"]).to eq("0")

    rebuild_post(fields, ip: "203.0.113.23")
    expect(response).to have_http_status(:found)
    created = Discussion::Comment.order(:id).last
    expect(created.status).to eq("approved")
    expect(created.moderation_verdicts.first.reason).to eq("author previously approved")
    expect(rebuild_row(created).except(:status)).to eq(oracle_row(expected["comment"]).except(:status))
  end

  admission("a reply to an approved comment", ip: "203.0.113.23") do
    parent = quoted_root_comment
    { "comment_post_ID" => parent["comment_post_ID"].to_i, "comment_parent" => parent["comment_ID"].to_i, "author" => "Reply Author",
      "email" => "reply.author@example.com", "comment" => "A reply, threaded under the root." }
  end

  # BR-MIGRATE-072 (BR-CMT-08): a moderation key holds the comment.
  admission("a comment matching a moderation key", ip: "203.0.113.24") do
    valid("author" => "Moderated Author", "email" => "moderated@example.com",
          "comment" => "Please moderate-me, I am new here.")
  end

  # BR-MIGRATE-071 (BR-CMT-07): three links against comment_max_links = 2.
  admission("a comment with more links than comment_max_links", ip: "203.0.113.25") do
    links = (1..3).map { |i| %(<a href="https://example.com/#{i}">link #{i}</a>) }
    valid("author" => "Link Author", "email" => "links@example.com", "comment" => "See #{links.join(", ")}.")
  end

  # Without consent and with a pending verdict, the redirect carries the two moderation
  # arguments (wp-comments-post.php:60-68).
  admission("a pending comment without cookie consent (moderation arguments on the redirect)", ip: "203.0.113.26") do
    valid("author" => "No Consent", "email" => "no.consent@example.com", "comment" => "No cookies for me.")
  end

  admission("a relative redirect_to, resolved against the script's directory", ip: "203.0.113.27") do
    valid("author" => "Relative Redirect", "email" => "relative@example.com",
          "comment" => "Back to a relative place.", "redirect_to" => "somewhere/else/")
  end

  admission("an absolute redirect_to on the site host, with an existing query string", ip: "203.0.113.28") do
    valid("author" => "Absolute Redirect", "email" => "absolute@example.com",
          "comment" => "Back to an absolute place.", "redirect_to" => "http://127.0.0.1:8099/some/path/?already=1")
  end

  admission("a redirect_to on a foreign host, which falls back to admin_url()", ip: "203.0.113.29") do
    valid("author" => "Foreign Redirect", "email" => "foreign@example.com",
          "comment" => "Trying to leave.", "redirect_to" => "http://evil.example/landing")
  end

  # Note: the foreign-host fallback above compares `<SITE>/wp-admin/` on both sides — the
  # legacy's literal admin_url(). The target's console lives elsewhere (target_screens.md);
  # keeping the literal is a recorded divergence, not an oversight.

  # BR-MIGRATE-069 (BR-CMT-05): a moderator's own submission is approved without checks,
  # and the identity fields come from the user record, whatever the form said.
  it "admits a logged-in moderator with the user's identity and an immediate approval (BR-MIGRATE-069)" do
    admin = CS_CORPUS["users"].find { |u| u["roles"].include?("administrator") }
    fields = { "comment_post_ID" => hello_world_id, "author" => "Ignored Name", "email" => "ignored@example.com",
               "url" => "http://ignored.example/", "comment" => "From the moderator's chair. <script>x</script>" }
    expected = oracle_submit([{ fields: fields, ip: "203.0.113.30", agent: CS_AGENT, user: admin["login"] }]).first
    expect(expected["error"]).to be_nil

    actor = Identity::User.find(admin["id"])
    allow_any_instance_of(Web::CommentsController).to receive(:current_actor).and_return(actor)
    rebuild_post(fields, ip: "203.0.113.30")

    expect(response).to have_http_status(:found)
    created = Discussion::Comment.order(:id).last
    expect(rebuild_row(created)).to eq(oracle_row(expected["comment"]))
    expect(created.status).to eq("approved")
    expect(created.user_id).to eq(actor.id)
    # wp_set_comment_cookies(): a logged-in user gets no cookies (comment.php:641).
    expect(Array(response.headers["Set-Cookie"]).join).not_to include("comment_author")
    # Without the unfiltered-html nonce a moderator is ksesed like anyone else
    # (comment.php:4083-4093).
    expect(created.content).not_to include("<script>")
  end

  # ════════════════════════════════════════════════════════════════════════════════
  # 3. Deviations — asserted as deviations, against what the oracle actually does.
  # ════════════════════════════════════════════════════════════════════════════════

  # BR-MIGRATE-074 (BR-CMT-10), approved deviation: the oracle trashes (EMPTY_TRASH_DAYS
  # is 30 there), the target marks spam, always.
  it "marks a disallowed-key match spam where the oracle trashes it (BR-MIGRATE-074 deviation)" do
    fields = valid("author" => "Disallowed Author", "email" => "disallowed@example.com",
                   "comment" => "Contains badword, plainly.")
    expected = oracle_submit([{ fields: fields, ip: "203.0.113.31", agent: CS_AGENT }]).first
    expect(expected["comment"]["comment_approved"]).to eq("trash")

    rebuild_post(fields, ip: "203.0.113.31")
    expect(response).to have_http_status(:found)
    created = Discussion::Comment.order(:id).last
    expect(created.status).to eq("spam")
    expect(rebuild_row(created).except(:status)).to eq(oracle_row(expected["comment"]).except(:status))
  end

  # BR-MIGRATE-068 (BR-CMT-04): a second submission from the same IP within 15 seconds is
  # a 429 flood on BOTH systems — the legacy does throttle (see Discussion::RateLimit).
  it "refuses a second submission from the same address within 15 seconds with 429" do
    first = valid("author" => "Rapid One", "email" => "rapid.one@example.com", "comment" => "First.")
    second = valid("author" => "Rapid Two", "email" => "rapid.two@example.com", "comment" => "Second.")
    # One PHP process, one transaction: the second submission sees the first's row.
    expected = CS_ORACLE.run(<<~PHP, JSON.generate(first: first, second: second))
      global $wpdb;
      $in = json_decode(file_get_contents('php://stdin'), true);
      $wpdb->query('START TRANSACTION');
      $_SERVER['REMOTE_ADDR'] = '203.0.113.32'; $_SERVER['HTTP_USER_AGENT'] = 'x';
      $a = wp_handle_comment_submission($in['first']);
      $b = wp_handle_comment_submission($in['second']);
      $wpdb->query('ROLLBACK');
      echo json_encode(array('first_ok' => !is_wp_error($a),
        'second' => is_wp_error($b) ? array($b->get_error_code(), $b->get_error_message(), (int) $b->get_error_data()) : null));
    PHP
    expect(expected["first_ok"]).to be(true)
    expect(expected["second"]).to eq(["comment_flood", "You are posting comments too quickly. Slow down.", 429])

    rebuild_post(first, ip: "203.0.113.32")
    expect(response).to have_http_status(:found)
    rebuild_post(second, ip: "203.0.113.32")
    expect(response.status).to eq(429)
    expect(response.body).to include("<p>You are posting comments too quickly. Slow down.</p>")
  end

  # ════════════════════════════════════════════════════════════════════════════════
  # 4. The commenter cookies — the HTTP half observed on the live oracle.
  # ════════════════════════════════════════════════════════════════════════════════

  # Observed with curl against the oracle (siteurl http://127.0.0.1:8099) on
  # 2026-08-22 18:28:48 UTC, consent given:
  #   Set-Cookie: comment_author_ae05d9aa32f40c913ab847dedf84e8cf=Probe%20One; expires=Sun, 22 Aug 2027 18:28:48 GMT; Max-Age=31536000; path=/
  #   Set-Cookie: comment_author_email_ae05d9aa32f40c913ab847dedf84e8cf=probe.one%40example.com; expires=…; Max-Age=31536000; path=/
  #   Set-Cookie: comment_author_url_ae05d9aa32f40c913ab847dedf84e8cf=http%3A%2F%2Fexample.com%2Fprobe; expires=…; Max-Age=31536000; path=/
  # and without consent:
  #   Set-Cookie: comment_author_ae05d9aa32f40c913ab847dedf84e8cf=%20; expires=Fri, 22 Aug 2025 18:28:48 GMT; Max-Age=0; path=/  (×3)
  it "derives COOKIEHASH as md5(siteurl), which is what the oracle's cookie names carry" do
    expect(Digest::MD5.hexdigest("http://127.0.0.1:8099")).to eq("ae05d9aa32f40c913ab847dedf84e8cf")
    expect(Discussion::CommenterCookies.cookie_hash).to eq(Digest::MD5.hexdigest("http://#{CS_HOST}"))
  end

  it "sets the three commenter cookies for a year when consent is given, PHP-encoded" do
    travel_to Time.utc(2026, 8, 22, 18, 28, 48)
    rebuild_post({ "comment_post_ID" => hello_world_id, "author" => "Probe <b>One</b>", "email" => "probe.one@example.com",
                   "url" => "example.com/probe", "comment" => "Cookies please.", "wp-comment-cookies-consent" => "yes" },
                 ip: "203.0.113.40")
    expect(response).to have_http_status(:found)
    h = Discussion::CommenterCookies.cookie_hash
    expect(Array(response.headers["Set-Cookie"])).to eq([
      "comment_author_#{h}=Probe%20One; expires=Sun, 22 Aug 2027 18:28:48 GMT; Max-Age=31536000; path=/",
      "comment_author_email_#{h}=probe.one%40example.com; expires=Sun, 22 Aug 2027 18:28:48 GMT; Max-Age=31536000; path=/",
      "comment_author_url_#{h}=http%3A%2F%2Fexample.com%2Fprobe; expires=Sun, 22 Aug 2027 18:28:48 GMT; Max-Age=31536000; path=/",
    ])
    # With consent, a pending comment's redirect carries NO moderation arguments.
    expect(response.location).to eq("http://#{CS_HOST}/2026/03/hello-world/#comment-#{Discussion::Comment.order(:id).last.id}")
  end

  it "removes the three commenter cookies when consent is withheld" do
    travel_to Time.utc(2026, 8, 22, 18, 28, 48)
    rebuild_post(valid("author" => "No Cookies", "email" => "no.cookies@example.com", "comment" => "No cookies."),
                 ip: "203.0.113.41")
    expect(response).to have_http_status(:found)
    h = Discussion::CommenterCookies.cookie_hash
    expect(Array(response.headers["Set-Cookie"])).to eq(
      %w[comment_author comment_author_email comment_author_url].map do |n|
        "#{n}_#{h}=%20; expires=Fri, 22 Aug 2025 18:28:48 GMT; Max-Age=0; path=/"
      end
    )
    created = Discussion::Comment.order(:id).last
    expect(response.location).to eq(
      "http://#{CS_HOST}/2026/03/hello-world/?unapproved=#{created.id}" \
      "&moderation-hash=#{Discussion::ModerationHash.for(created)}#comment-#{created.id}"
    )
    expect(Discussion::ModerationHash.valid?(created, Discussion::ModerationHash.for(created))).to be(true)
  end
end
