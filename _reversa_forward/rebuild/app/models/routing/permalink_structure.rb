# frozen_string_literal: true

module Routing
  # AGG-Permalink -- target_domain_model.md AGG-Permalink.
  #
  # "The reserved-segment set (pagination base, registered feed slugs, `embed`,
  #  date-archive segments) is DERIVED FROM THE STRUCTURE, and slug allocation consults
  #  it. This is the genuine legacy coupling made explicit rather than inherited."
  #  (BR-MIGRATE-034, F-RW-06)
  #
  # migration_strategy.md lists rewrite <-> query as the one cycle edge that "survives
  # genuinely": routing configuration constrains slug validation. It is modelled
  # deliberately here -- Routing reads Publishing and Configuration, never the reverse --
  # and Publishing consults the reserved set through the port it owns
  # (Publishing.reserved_segments), so no back-edge is created.
  class PermalinkStructure
    DEFAULT_PATTERN = "/%year%/%monthnum%/%postname%/"

    # The pagination base and the feed slugs are what F-RW-06 names; `embed` and the
    # infrastructure paths follow from the routes the system itself owns.
    #
    # BR-MIGRATE-144 (BR-RW-04): pagination_base is 'page', comments_pagination_base is
    # 'comment-page'. BR-MIGRATE-143 (BR-RW-03): the built-in feed slugs are exactly
    # feed, rdf, rss, rss2, atom -- confirmed against the live oracle
    # ($wp_rewrite->feeds).
    DEFAULT_PAGINATION_BASE = "page"
    DEFAULT_COMMENTS_PAGINATION_BASE = "comment-page"
    DEFAULT_FEED_SLUGS = %w[feed rdf rss rss2 atom].freeze
    ALWAYS_RESERVED = %w[embed trackback comments wp-json wp-admin wp-content wp-includes].freeze

    # BR-MIGRATE-141 (BR-RW-01). The legacy holds these as THREE positionally aligned
    # arrays -- rewritecode, rewritereplace, queryreplace -- and compiles by substituting
    # index for index, "with nothing enforcing the alignment". One map keyed by the token
    # cannot fall out of alignment, which is the whole reason it is one map here.
    #
    # BR-MIGRATE-142 (BR-RW-02) is the part a naive port loses: %pagename% is NON-GREEDY
    # because pages are hierarchical, %postname% is greedy, and %search% may contain
    # slashes.
    TOKENS = {
      "year" => ['([0-9]{4})', "year"],
      "monthnum" => ['([0-9]{1,2})', "monthnum"],
      "day" => ['([0-9]{1,2})', "day"],
      "hour" => ['([0-9]{1,2})', "hour"],
      "minute" => ['([0-9]{1,2})', "minute"],
      "second" => ['([0-9]{1,2})', "second"],
      "post_id" => ['([0-9]+)', "p"],
      "postname" => ['([^/]+)', "name"],
      "pagename" => ['([^/]+?)', "pagename"],
      "category" => ['(.+?)', "category_name"],
      "tag" => ['([^/]+)', "tag"],
      "author" => ['([^/]+)', "author_name"],
      "search" => ['(.+)', "s"]
    }.freeze

    # One compiled rule. The legacy's rule set is a flat hash of regex => query string
    # (BR-MIGRATE-145) that it then stores in a single option; here it is derived state
    # with no storage at all (AD-06).
    Rule = Struct.new(:regex, :query, keyword_init: true)

    # The observable answer to "change the structure". Carries the RECOMPUTED table and
    # any records the new structure would shadow, so the conflict is surfaced instead of
    # being silently resolved by renaming somebody's published record.
    Change = Struct.new(:structure, :route_table, :reserved_segments, :conflicts, :applied,
                        keyword_init: true) do
      def conflict? = conflicts.any?
      def applied? = !!applied
    end

    attr_reader :pattern, :pagination_base, :comments_pagination_base, :feed_slugs

    def initialize(pattern: DEFAULT_PATTERN, pagination_base: DEFAULT_PAGINATION_BASE,
                   feed_slugs: DEFAULT_FEED_SLUGS,
                   comments_pagination_base: DEFAULT_COMMENTS_PAGINATION_BASE)
      @pattern = pattern
      @pagination_base = pagination_base
      @comments_pagination_base = comments_pagination_base
      @feed_slugs = feed_slugs
    end

    def self.current
      new(pattern: Configuration::Setting["permalink_structure"].presence || DEFAULT_PATTERN)
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      new
    end

    # Accepted command `set_structure` + `recompile` (target_domain_model.md
    # AGG-Permalink), as one operation because they are one fact: the reserved set and
    # the route table are DERIVED from the structure, so changing it recomputes both.
    #
    # A structure that would shadow an already-published slug is REFUSED and the
    # collision reported. The legacy has no such notion -- wp_unique_post_slug() only
    # ever runs on write, so flipping the permalink structure afterwards silently leaves
    # a post that can no longer be reached. Surfacing beats silently resolving: nothing
    # here renames a published record behind its author's back.
    def self.change_to(pattern, pagination_base: DEFAULT_PAGINATION_BASE,
                       feed_slugs: DEFAULT_FEED_SLUGS)
      candidate = new(pattern: pattern, pagination_base: pagination_base, feed_slugs: feed_slugs)
      conflicts = candidate.shadowed_records.to_a
      applied = false

      if conflicts.empty?
        Configuration::Setting.set("permalink_structure", pattern)
        applied = true
      end

      Change.new(structure: candidate, route_table: candidate.route_table,
                 reserved_segments: candidate.reserved_segments, conflicts: conflicts,
                 applied: applied)
    end

    # DERIVED, never stored. AD-06: "The compiled route table is derived state, cached
    # and rebuildable -- never a stored setting." The legacy kept it in an autoloaded
    # option that the 150 KB threshold could silently de-autoload (F-RW-02, BR-OPT-06).
    def reserved_segments
      segments = [pagination_base, comments_pagination_base] + feed_slugs + ALWAYS_RESERVED
      # A structure whose leading token is literal reserves that literal too:
      # /blog/%postname%/ makes "blog" unavailable as a post slug.
      segments.concat(literal_segments)
      segments.map(&:to_s).uniq.to_set
    end

    # BR-MIGRATE-034 (BR-POST-07) in full: a registered feed name, 'embed', A PAGINATION
    # NUMBER, or a date-archive segment. The last two are not set membership -- they are
    # shapes -- so membership alone is not the whole rule.
    def reserved?(value)
      slug = value.to_s
      return false if slug.empty?
      return true if reserved_segments.include?(slug)
      return true if pagination_number?(slug)

      shadows_date_archive?(slug)
    end

    # `^($pagination_base)?\d+$` -- wp-includes/post.php:5647. "page2" and "2" both.
    def pagination_number?(slug)
      slug.to_s.match?(/\A(?:#{Regexp.escape(pagination_base)})?\d+\z/)
    end

    # wp-includes/post.php:5666. An all-digit slug can be read as a date segment when
    # %postname% sits first in the structure, or directly after %year% (<= 12) or after
    # %monthnum% (<= 31).
    def shadows_date_archive?(slug)
      return false unless slug.to_s.match?(/\A[0-9]+\z/)

      number = slug.to_i
      return false if number.zero?

      structs = pattern.to_s.split("/").reject(&:empty?)
      index = structs.index("%postname%")
      return false if index.nil?
      return true if index.zero?

      previous = structs[index - 1]
      (previous == "%year%" && number < 13) || (previous == "%monthnum%" && number < 32)
    end

    # Published records whose slug the given structure would swallow. Routing -> Publishing
    # is the permitted edge; the reverse would re-form the cycle (target_architecture.md
    # Note 2).
    def shadowed_records
      Publishing::Post.where.not(slug: nil).select { |post| reserved?(post.slug) }
    end

    # AD-06: computed on demand from the structure, memoised per instance, stored nowhere.
    # Rebuilding it is a method call, not a migration -- which is the point of taking it
    # out of `options` (BR-MIGRATE-145/146: the legacy stores the whole set in one option
    # and regenerates when that option comes back empty).
    def route_table
      @route_table ||= compile
    end

    def tokens = pattern.to_s.scan(/%([a-z_]+)%/).flatten

    # The path a record occupies under this structure. Used to record where a renamed
    # record USED to live (AD-03).
    def path_for(post, slug: post.slug)
      at = (post.published_at || post.created_at || Time.current)
      rendered = pattern.to_s.gsub(/%([a-z_]+)%/) { substitute(Regexp.last_match(1), post, slug, at) }
      normalize_path(rendered)
    end

    def normalize_path(path)
      cleaned = path.to_s.squeeze("/")
      cleaned = "/#{cleaned}" unless cleaned.start_with?("/")
      cleaned = "#{cleaned}/" unless cleaned.end_with?("/")
      cleaned
    end

    private

    def literal_segments
      pattern.to_s.split("/").reject { |s| s.empty? || s.start_with?("%") }
    end

    def substitute(token, post, slug, at)
      case token
      when "year" then format("%04d", at.year)
      when "monthnum" then format("%02d", at.month)
      when "day" then format("%02d", at.day)
      when "hour" then format("%02d", at.hour)
      when "minute" then format("%02d", at.min)
      when "second" then format("%02d", at.sec)
      when "post_id" then post.id.to_s
      when "postname", "pagename" then slug.to_s
      when "author" then post.author&.nicename.to_s
      else ""
      end
    end

    # BR-MIGRATE-141/142/143/144, compiled together because they are one derivation.
    def compile
      base, query, captures = compile_base
      feeds = feed_slugs.join("|")

      [
        Rule.new(regex: "#{base}/feed/(#{feeds})/?$", query: "#{query}&feed=$#{captures + 1}"),
        Rule.new(regex: "#{base}/(#{feeds})/?$", query: "#{query}&feed=$#{captures + 1}"),
        Rule.new(regex: "#{base}/#{pagination_base}/?([0-9]{1,})/?$",
                 query: "#{query}&paged=$#{captures + 1}"),
        Rule.new(regex: "#{base}/#{comments_pagination_base}-([0-9]{1,})/?$",
                 query: "#{query}&cpage=$#{captures + 1}"),
        Rule.new(regex: "#{base}/embed/?$", query: "#{query}&embed=true"),
        Rule.new(regex: "#{base}/trackback/?$", query: "#{query}&tb=1"),
        Rule.new(regex: "#{base}/?$", query: query)
      ]
    end

    def compile_base
      captures = 0
      query = []
      regex = pattern.to_s.split("/").reject(&:empty?).map do |segment|
        token = segment[/\A%([a-z_]+)%\z/, 1]
        if token && TOKENS.key?(token)
          pattern_source, var = TOKENS.fetch(token)
          captures += 1
          query << "#{var}=$#{captures}"
          pattern_source
        else
          Regexp.escape(segment)
        end
      end.join("/")

      [regex, query.join("&"), captures]
    end
  end
end
