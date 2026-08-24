# frozen_string_literal: true

require "nokogiri"

module Parity
  # Response normalization for the diff harness.
  #
  # The rules are NOT invented here — they are transcribed from
  # `_reversa_sdd/screens/golden/manifest.yaml § normalizationRules`, and each carries
  # the reason it exists. A normalization without a reason is a parity test quietly
  # deciding not to look at something.
  #
  # ⚠️ The danger of this file is over-normalization: every rule below removes a class of
  # difference from view permanently, and AD-01 means there is no filter to restore it.
  # Nothing should be added here without a recorded justification.
  class Normalizer
    # Nonces are per-session and can never be compared between two runs, let alone two
    # systems. `stripNonces: true`.
    NONCE_PATTERNS = [
      /(_wpnonce=)[0-9a-f]{10}/i,
      /(name="_wpnonce"\s+value=")[0-9a-f]{10}/i,
      /(nonce":")[0-9a-f]{10}/i,
      /(-nonce="?)[0-9a-f]{10}/i,
      # The oEmbed `data-secret` is a per-request wp_generate_password(10) token used to
      # pair an iframe with its parent across origins. It is a nonce in everything but
      # name, and it appears three times per embed (attribute, src fragment, and again
      # HTML-escaped inside the shareable textarea) -- so it is matched by VALUE, not by
      # attribute, to catch all three.
      /(secret=&quot;)[A-Za-z0-9]{10}/,
      /(secret=")[A-Za-z0-9]{10}/,
      /(secret=)[A-Za-z0-9]{10}/,
    ].freeze

    # `stripGuid: true` — T-07: the target generates a fresh UUID, so guid differs from
    # the oracle BY DESIGN. data_migration_plan.md: "The harness must normalize it, or it
    # fails on every feed."
    GUID_PATTERNS = [
      %r{<guid[^>]*>.*?</guid>}m,
      # The Atom feed exposes the SAME guid as its entry `<id>` (`the_guid()`,
      # wp-includes/feed-atom.php:79) — same declared rule, different element name.
      # Anchored to the entry indentation (two tabs, feed-atom.php's own layout); the
      # feed-level `<id>` sits at one tab and stays comparable. No other surface in the
      # corpus emits a two-tab `<id>` line.
      %r{^\t\t<id>.*</id>$},
      /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i,
    ].freeze

    # `stripAutoincrementIds: true` — post and comment ids differ between the oracle and
    # the target because the target's sequences start fresh.
    ID_PATTERNS = [
      /\b(post-)\d+\b/,
      /\b(comment-)\d+\b/,
      # get_the_password_form(), wp-includes/post-template.php:1781: the password field's
      # id is `'pwbox-' . $post->ID` — the same autoincrement post id `post-<n>` carries.
      /\b(pwbox-)\d+\b/,
      /\b(page-id-)\d+\b/,
      /\b(postid-)\d+\b/,
      /\b(cat-item-)\d+\b/,
      /\b(menu-item-)\d+\b/,
      /(\?p=)\d+/,
      /(\?page_id=)\d+/,
      /(\bid="comment-)\d+/,
      # The REST discovery links embed the record's id in the path. Same declared rule
      # (`stripAutoincrementIds`): the rebuild's sequences start from 1 while the oracle's
      # have counted every revision and machinery row the corpus ever created, so ids
      # cannot line up and were never meant to.
      %r{(/wp-json/wp/v2/[a-z_]+/)\d+},
    ].freeze

    # `seedRandom: 42` — WordPress generates per-request widget ids to wire ARIA
    # relationships (wp_unique_id / rand()), e.g.
    #   aria-controls="wp-embed-share-tab-wordpress-1-3624864193"
    # PHP's randomness cannot be seeded from outside the process, so the manifest's
    # seed-the-RNG rule is implemented here as normalization instead. These ids are
    # per-request by construction: they can never be compared between two runs, let
    # alone between two systems, and only the RELATIONSHIP between the pairs matters.
    #
    # ⚠️ Deliberately narrow. It matches the generated-id shape only, so a numeric suffix
    # that carries meaning is left alone.
    GENERATED_ID_PATTERNS = [
      /(wp-embed-share-[a-z-]*?-\d+-)\d{6,}/,
      /(wp-unique-id-)\d{6,}/,
    ].freeze

    # `injectClock: 2026-01-01T00:00:00Z` — anything that renders "now" is not a
    # behavioural difference.
    TIME_PATTERNS = [
      /\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([+-]\d{2}:\d{2}|Z)/,
      /\b(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun),\s+\d{1,2}\s+\w{3}\s+\d{4}\s+\d{2}:\d{2}:\d{2}\s+[+-]\d{4}/,
      /\bver=\d+\.\d+(\.\d+)?(-\w+)?/,
    ].freeze

    def initialize(rules: {})
      @rules = {
        line_endings: "\n", normalize_utf8: true, strip_nonces: true,
        strip_autoincrement_ids: true, strip_guid: true,
        collapse_whitespace_between_tags: true, sort_class_attribute_tokens: true,
        inject_clock: "2026-01-01T00:00:00Z",
      }.merge(rules)
    end

    def call(body, content_type: "text/html")
      s = body.to_s.dup

      # ⚠️ `normalizeUtf8` must RE-TAG the bytes, never TRANSCODE them.
      #
      # Net::HTTP hands back an ASCII-8BIT string. `String#encode(UTF_8, invalid:
      # :replace)` from binary treats every BYTE as a character, so one emoji becomes
      # four U+FFFD -- and it does so on both sides of the diff, which is what makes the
      # bug so dangerous: the two systems look identical while the comparison has been
      # flattened out of existence. That is precisely RISK-014, "a divergence in the
      # permissive direction that diffing tends to miss."
      #
      # The bytes were always UTF-8; only the tag was wrong. force_encoding fixes the tag
      # and scrub drops genuinely invalid sequences without touching valid ones.
      if @rules[:normalize_utf8]
        s = s.force_encoding(Encoding::UTF_8)
        s = s.scrub unless s.valid_encoding?
      end
      s = s.gsub(/\r\n?/, @rules[:line_endings])

      GUID_PATTERNS.each { |re| s = s.gsub(re, "<GUID>") } if @rules[:strip_guid]
      NONCE_PATTERNS.each { |re| s = s.gsub(re) { "#{Regexp.last_match(1)}<NONCE>" } } if @rules[:strip_nonces]
      ID_PATTERNS.each { |re| s = s.gsub(re) { "#{Regexp.last_match(1)}<ID>" } } if @rules[:strip_autoincrement_ids]
      TIME_PATTERNS.each { |re| s = s.gsub(re, "<TIME>") }
      GENERATED_ID_PATTERNS.each { |re| s = s.gsub(re) { "#{Regexp.last_match(1)}<UID>" } }

      # Absolute self-links differ only by host between the two systems — the oracle is
      # on :8099 and the rebuild on :3100 by construction, so the host is never a
      # behavioural difference.
      s = s.gsub(%r{https?://(?:127\.0\.0\.1|localhost)(?::\d+)?}, "<SITE>")
      # ⚠️ And again PERCENT-ENCODED. The oEmbed discovery links carry the permalink
      # inside a query parameter (`?url=http%3A%2F%2F127.0.0.1%3A8099%2F…`), so the plain
      # rule above never sees it and two otherwise byte-identical pages differ on the
      # host alone. Same rule, same justification, different encoding — not a second
      # normalization.
      s = s.gsub(/https?%3A%2F%2F(?:127\.0\.0\.1|localhost)(?:%3A\d+)?/i, "<SITE-ENC>")

      if html?(content_type)
        s = sort_class_tokens(s) if @rules[:sort_class_attribute_tokens]
        s = s.gsub(/>\s+</, ">\n<") if @rules[:collapse_whitespace_between_tags]
      end
      s.strip
    end

    private

    def html?(content_type) = content_type.to_s.include?("html")

    # `sortClassAttributeTokens: true` — "block supports concatenate classes in
    # registration order (F-BSUP-01), which the target does not reproduce."
    # ⚠️ Note this normalization hides BR-MIGRATE-201 (first writer takes the slot, later
    # ones append). That rule must therefore be asserted by a unit test in the `styling`
    # pack, not by the screen diff — the screen diff can no longer see it.
    def sort_class_tokens(html)
      html.gsub(/\sclass="([^"]*)"/) do
        tokens = Regexp.last_match(1).split(/\s+/).reject(&:empty?).sort
        %( class="#{tokens.join(" ")}")
      end
    end
  end
end
