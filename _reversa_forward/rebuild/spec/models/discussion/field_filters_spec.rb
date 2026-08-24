# frozen_string_literal: true

require "rails_helper"
require_relative "../presentation/oracle"

# DIFFERENTIAL. Discussion::FieldFilters inlines the `pre_comment_*` save filters
# (wp-includes/default-filters.php, kses.php:2545). The expectation for every input is
# the oracle's own `apply_filters('pre_comment_<field>', …)` — run in one PHP process over
# the whole corpus — and nothing here is a paraphrase of formatting.php.
#
# ⚠️ RISK-008. The legacy filters expect SLASHED input (wp_filter_kses stripslashes /
# addslashes around kses; wp_rel_ugc likewise), and the comment path wp_slash()es before
# and wp_unslash()es after (comment.php:4148, :2159). So the PHP side is asked for
# `wp_unslash( apply_filters( $filter, wp_slash( $raw ) ) )` — the value as it reaches the
# table — and the Ruby side is given the raw string. That is the equivalence the
# differential checks, backslash corpus included.
RSpec.describe Discussion::FieldFilters do
  # Constants inside a describe block land on Object, so they are prefixed to stay out of
  # every other spec's way.
  FF_ORACLE = Presentation::SpecOracle

  FF_CORPUS = [
    "plain text",
    "He said \"it's a test\" -- she replied '\"nested\"' ... 5'9\" tall, 3\" wide « French » 「日本語」 ‘curly’ “already curly”",
    'Windows path C:\\Users\\thies\\file.txt — regex \\d+\\s*\\\\ — literal \\n not a newline — LaTeX \\frac{1}{2} — escaped quote \\" and \\\'',
    "Emoji 😀🧬🚀 · Math 𝔘𝔫𝔦𝔠𝔬𝔡𝔢 · ZWJ 👨‍👩‍👧‍👦 · Flag 🇯🇵",
    "a <b>bold</b> <i>it</i> <strong>s</strong> <em>e</em> <script>alert(1)</script> <img src=x onerror=alert(2)> end",
    "<a href=\"http://example.com/\">external</a> <a href=\"http://127.0.0.1:8099/x\">internal</a> <a href=\"/rel\">relative</a>",
    "<a href=\"https://example.com/\" rel=\"me\">with rel</a> <a href='javascript:alert(1)'>js</a> <a href=\"feed:javascript:alert(6)\">feed</a>",
    "<a href=\"http://Example.COM/\" title=\"t &quot;q&quot;\" rel=\"nofollow\">already nofollow</a>",
    "<span class=\"x wp-note-mention user-3 y\">m</span> <span class=\"nope\">n</span> <span>p</span> <span class=\"user-0 user-12\">q</span>",
    "&#147;smart&#148; &#128; &#129; &#133; &#1; &#1234; &amp; &lt; &gt; &copy; &bogus; &#x27;",
    "line one\nline two\r\n\ttabbed   spaced",
    "<p>Unclosed tag <b>bold forever",
    "<table><tr><td>cell</td></tr></table> <blockquote cite=\"x\">q</blockquote> <code>c</code> <del datetime=\"d\">d</del>",
    "  leading and trailing  ",
    "null\0byte and \x0Bvertical tab",
    "percent %41 %zz %4 encoded",
    "O<b>x</b>'Brien & \"Co\" <script>y</script>",
    "<!-- comment --> <![CDATA[x]]> <?php echo 1; ?> < lone lt > and 3 < 4",
    "<a href=\"http://127.0.0.1:8099/\" rel=\"external nofollow\">merged</a><a href=\"http://x.y\" REL=\"A\">caps</a>",
    "<A HREF=\"HTTP://EXAMPLE.COM/\">upper</A> <a\nhref=\"http://n.l/\">newline attr</a>",
  ].freeze

  FF_EMAILS = [
    "probe.one@example.com", " A.B@Exa mple.com ", "bad", "no-at.example.com", "a@b", "x@y.z",
    "O'Brien@example.com", "a..b@c..d.e", "trail@example.com.", "a@-b.c", "a\\b@example.com",
    "a<b>c</b>@example.com", "用户@example.com", "a@b.c\n", "\"quoted\"@example.com", "a@b.c-d.e",
  ].freeze

  FF_URLS = [
    "example.com/probe", "http://example.com/a b<i>c</i>", "javascript:alert(1)", "/relative/path",
    "ftp://x.y/z", "  http://x.y/?a=1&b=2  ", "http://x.y/'q'", "mailto:a@b.c", "x.php", "#frag",
    "http://ex.com/\\path", "http://[::1]/", "data:text/html,x", "https://例え.jp/", "",
  ].freeze

  FF_NAMES = [
    "Probe <b>One</b>", " O<b>x</b>'Brien & \"Co\" %41 ", "Plain Name", "tabs\tand\nnewlines",
    "<script>alert(1)</script>x", "null\0byte", "Commenter \"root-approved\" O'Brien 😀",
    "a %20 b %0a c", "< lone", "&amp; &lt; &copy; &#39;", "C:\\Users\\thies", "日本語 名前",
  ].freeze

  FF_FILTERED = FF_ORACLE.available? ? FF_ORACLE.run(<<~PHP, JSON.generate(content: FF_CORPUS, email: FF_EMAILS, url: FF_URLS, name: FF_NAMES)) : nil
    $in = json_decode(file_get_contents('php://stdin'), true);
    $map = array('content' => 'pre_comment_content', 'email' => 'pre_comment_author_email',
                 'url' => 'pre_comment_author_url', 'name' => 'pre_comment_author_name');
    $out = array('is_email' => array());
    foreach ($map as $key => $filter) {
      $out[$key] = array();
      foreach ($in[$key] as $raw) {
        // wp_handle_comment_submission(): author is trim(strip_tags()), the rest trim().
        $value = $key === 'name' ? trim(strip_tags($raw)) : trim($raw);
        $out[$key][] = wp_unslash(apply_filters($filter, wp_slash($value)));
      }
    }
    foreach ($in['email'] as $raw) { $out['is_email'][] = (bool) is_email(trim($raw)); }
    $out['home_host'] = wp_parse_url(home_url(), PHP_URL_HOST);
    echo json_encode($out, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
  PHP

  before do
    skip "the PHP oracle is not available" if FF_FILTERED.nil?
    Configuration::Setting.set("home", "http://127.0.0.1:8099")
  end

  def trimmed(s) = Discussion::FieldFilters.utf8(Discussion::FieldFilters.php_trim(s))

  it "filters comment content exactly as pre_comment_content does for an anonymous submitter" do
    FF_CORPUS.each_with_index do |raw, i|
      expect(described_class.content(trimmed(raw), html_filter: :restricted))
        .to eq(FF_FILTERED["content"][i]), "content corpus ##{i}: #{raw.inspect}"
    end
  end

  it "filters the author name exactly as pre_comment_author_name does" do
    FF_NAMES.each_with_index do |raw, i|
      handler_value = trimmed(Sanitizing::Formatting.strip_tags(raw.b))
      expect(described_class.author_name(handler_value)).to eq(FF_FILTERED["name"][i]), "name ##{i}: #{raw.inspect}"
    end
  end

  it "filters the email exactly as pre_comment_author_email does, and agrees with is_email()" do
    FF_EMAILS.each_with_index do |raw, i|
      expect(described_class.author_email(trimmed(raw))).to eq(FF_FILTERED["email"][i]), "email ##{i}: #{raw.inspect}"
      expect(described_class.is_email?(trimmed(raw))).to eq(FF_FILTERED["is_email"][i]), "is_email ##{i}: #{raw.inspect}"
    end
  end

  it "filters the URL exactly as pre_comment_author_url does" do
    FF_URLS.each_with_index do |raw, i|
      expect(described_class.author_url(trimmed(raw))).to eq(FF_FILTERED["url"][i]), "url ##{i}: #{raw.inspect}"
    end
  end

  it "leaves content unksesed for an unfiltered_html holder with a valid nonce, but still adds rel=ugc" do
    out = described_class.content("<script>x</script> <a href=\"http://example.com/\">l</a>", html_filter: :none)
    expect(out).to eq("<script>x</script> <a href=\"http://example.com/\" rel=\"nofollow ugc\">l</a>")
  end
end
