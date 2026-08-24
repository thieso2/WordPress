# frozen_string_literal: true

module Retrieval
  # BC-08 -- WP_Query's 4,900-line god-object (F-QUERY-07) becomes scopes and a query
  # object. Rules BR-MIGRATE-040..051.
  #
  # Several rules in that range describe the hook mechanism rather than behaviour and are
  # simply gone under AD-01:
  #   * BR-MIGRATE-040 -- `do_parse_request` returning false skips request parsing.
  #     There is no filter, so request parsing always happens.
  #   * BR-MIGRATE-051 -- every SQL clause is filterable twice and `posts_pre_query` can
  #     replace the query altogether. No clause is filterable; the query is what this
  #     object builds.
  #   * BR-MIGRATE-046 -- the split-query optimisation applies "only when NO FILTER
  #     ALTERED THE SQL and either a persistent object cache exists or
  #     posts_per_page < 500". The filter half of that condition cannot fail here, and
  #     the optimisation itself is a MySQL-era workaround: it exists because MySQL
  #     materialises a large row set before applying LIMIT. PostgreSQL does not need it.
  #   * BR-MIGRATE-049/050 -- cache priming on the first the_post(), and loop_end /
  #     loop_no_results actions. Rails eager-loads via `includes`, and there are no
  #     actions to fire.
  # Each is recorded here rather than silently omitted, per the Curator's contract.
  class PostQuery
    # ⚠️ BR-MIGRATE-041 (BR-QUERY-02) -- THE BOUNDARY THAT KEEPS DRAFTS PRIVATE.
    #
    # "Private query vars such as post_status, post__in and fields can never be set from
    #  the URL."
    #
    # In the legacy this is a denylist applied to the public query-var list. Here it is an
    # ALLOWLIST, because a denylist is only as good as its last update and this is the one
    # rule in the range whose failure mode is disclosing unpublished content. Anything not
    # named here is ignored when the input is untrusted.
    PUBLIC_VARS = %i[
      author category_name tag taxonomy term s search paged page year monthnum day
      post_type name order orderby posts_per_page
    ].freeze

    PRIVATE_VARS = %i[post_status post__in post__not_in fields meta_key meta_value
                      include exclude suppress_filters].freeze

    DEFAULT_PER_PAGE = 10
    MAX_PER_PAGE = 100

    attr_reader :vars, :trusted

    # `trusted: false` is the default on purpose: a caller that forgets to say where the
    # input came from gets the safe reading.
    def initialize(vars = {}, trusted: false)
      @trusted = trusted
      @vars = normalize(vars)
    end

    # BR-MIGRATE-041: from a URL, private vars are DROPPED, not rejected -- the legacy
    # ignores them silently and a 400 here would be a behavioural difference.
    def self.from_request(params)
      new(params.to_h.symbolize_keys, trusted: false)
    end

    def relation
      scope = base_scope
      scope = scope.where(author_id: vars[:author]) if vars[:author].present?
      scope = apply_type(scope)
      scope = apply_status(scope)
      scope = apply_date(scope)
      scope = apply_search(scope)
      scope = apply_taxonomy(scope)
      scope.order(order_clause)
    end

    def page = [vars.fetch(:paged, 1).to_i, 1].max

    def per_page
      requested = vars.fetch(:posts_per_page, DEFAULT_PER_PAGE).to_i
      requested = DEFAULT_PER_PAGE if requested <= 0
      [requested, MAX_PER_PAGE].min
    end

    def offset = (page - 1) * per_page

    def records = relation.offset(offset).limit(per_page)

    # BR-MIGRATE-047 (BR-QUERY-08): found_posts is computed "only when a LIMIT is present
    # and no_found_rows is false". MySQL's SELECT FOUND_ROWS() has no PostgreSQL
    # equivalent, so the count is a second query -- the same information, honestly priced.
    def total = @total ||= relation.count

    # BR-MIGRATE-047 (BR-QUERY-08), second half. class-wp-query.php:3699 bails out of
    # set_found_posts() when the page came back with NO rows -- "Bail if posts is an
    # empty array" -- which leaves both found_posts and max_num_pages at the 0 they were
    # initialised to. An out-of-range page therefore reports ZERO pages, not the real
    # count, and that is load-bearing: it is what makes core/query-pagination-numbers
    # emit nothing (and core/query-pagination suppress its whole <nav>) past the last
    # page, instead of a list of links back into the middle of the loop.
    def total_pages
      return 0 if records.empty?

      per_page.positive? ? (total.to_f / per_page).ceil : 0
    end

    # BR-MIGRATE-045 (BR-QUERY-06): "An empty author, term or post-type archive returns
    # 200 if the queried object EXISTS; an empty PAGED archive always 404s."
    #
    # The asymmetry is deliberate and easy to get wrong: /author/nobody/ with no posts is
    # a legitimate empty archive, while /author/nobody/page/7/ is a URL that never had
    # content and should not be indexed.
    def not_found?(queried_object_exists: true)
      return true unless queried_object_exists
      return true if page > 1 && records.empty?

      false
    end

    private

    def base_scope = Publishing::Post.all

    def normalize(input)
      symbolized = input.to_h.symbolize_keys
      allowed = trusted ? symbolized : symbolized.slice(*PUBLIC_VARS)
      if !trusted && (leaked = symbolized.keys & PRIVATE_VARS).any?
        # Dropped silently, as the legacy does -- but counted, because a private var
        # arriving from a URL is worth being able to see.
        Rails.logger&.info("Retrieval::PostQuery dropped private vars from untrusted input: #{leaked.inspect}")
      end
      allowed
    end

    # An ABSENT post_type is not "all types". WP_Query defaults it to `post` — which is
    # why the home loop never lists pages — EXCEPT under a search, where the type set
    # widens to every type with `exclude_from_search = false`, i.e. post AND page.
    # Verified against the oracle, not inferred: `new WP_Query(["s" => "page"])` returns
    # pages; the front page golden contains none. Returning the unfiltered scope here is
    # how "Sample Page" and "Privacy Policy" leaked into the rebuild's home loop.
    SEARCHABLE_TYPES = %w[Publishing::Article Publishing::Page].freeze

    def apply_type(scope)
      requested = vars[:post_type]
      if requested.blank?
        return scope.where(type: SEARCHABLE_TYPES) if vars[:s].present? || vars[:search].present?

        return scope.where(type: "Publishing::Article")
      end

      klass = { "post" => "Publishing::Article", "page" => "Publishing::Page" }[requested.to_s]
      klass ? scope.where(type: klass) : scope.none
    end

    # The other half of BR-MIGRATE-041. An untrusted query may never widen the status set
    # beyond what is publicly visible, whatever else it asks for.
    def apply_status(scope)
      return scope.where(status: vars[:post_status]) if trusted && vars[:post_status].present?

      scope.where(status: %w[published])
    end

    def apply_date(scope)
      return scope if vars[:year].blank?

      year = vars[:year].to_i
      from = Time.utc(year, vars[:monthnum].presence&.to_i || 1, vars[:day].presence&.to_i || 1)
      to = if vars[:day].present?   then from + 1.day
           elsif vars[:monthnum].present? then from + 1.month
           else from + 1.year
           end
      scope.where(published_at: from...to)
    end

    # BR-MIGRATE-048 (BR-QUERY-09): "Search terms that are single a-z or dash characters,
    # or locale stopwords, are dropped. Quoted terms keep their surrounding spaces to
    # signal exact-match."
    STOPWORDS = %w[
      about an are as at be by com for from how in is it of on or that the this to was
      what when where who will with www
    ].freeze

    def self.search_terms(raw)
      terms = []
      remaining = raw.to_s.dup
      # Quoted phrases first, so their internal spaces survive.
      remaining = remaining.gsub(/"([^"]*)"/) do
        terms << { value: Regexp.last_match(1), exact: true }
        " "
      end
      remaining.split(/\s+/).reject(&:empty?).each do |word|
        next if word.match?(/\A[a-z-]\z/i)          # single a-z or dash
        next if STOPWORDS.include?(word.downcase)   # locale stopwords

        terms << { value: word, exact: false }
      end
      terms
    end

    def apply_search(scope)
      raw = vars[:s].presence || vars[:search].presence
      return scope if raw.blank?

      terms = self.class.search_terms(raw)
      return scope if terms.empty?

      terms.reduce(scope) do |acc, term|
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term[:value])}%"
        acc.where("posts.title ILIKE :p OR posts.content ILIKE :p OR posts.excerpt ILIKE :p", p: pattern)
      end
    end

    def apply_taxonomy(scope)
      slug = vars[:category_name].presence || vars[:tag].presence || vars[:term].presence
      return scope if slug.blank?

      taxonomy = vars[:taxonomy].presence || (vars[:tag].present? ? "post_tag" : "category")
      term = Classification::Term.joins(:taxonomy)
                                 .find_by(slug: slug, taxonomies: { name: taxonomy })
      return scope.none if term.nil?

      ids = term.self_and_descendant_ids
      scope.where(id: Classification::Assignment.where(term_id: ids,
                                                       classifiable_type: "Publishing::Post")
                                                .select(:classifiable_id))
    end

    # RISK-007: MySQL and PostgreSQL disagree on the default null ordering, and every
    # draft carries a NULL published_at (it carried '0000-00-00 00:00:00' in the legacy).
    # NULLS LAST is stated explicitly wherever ordering matters.
    def order_clause
      direction = vars[:order].to_s.downcase == "asc" ? "ASC" : "DESC"
      column = case vars[:orderby].to_s
               when "title"    then "posts.title"
               when "modified" then "posts.modified_at"
               when "menu_order" then "posts.menu_order"
               when "id"       then "posts.id"
               else "posts.published_at"
               end
      nulls = direction == "DESC" ? "NULLS LAST" : "NULLS FIRST"
      base = "#{column} #{direction} #{nulls}, posts.id #{direction}"
      rank = search_order_clause
      Arel.sql(rank ? "#{rank}, #{base}" : base)
    end

    # WP_Query::parse_search_order(), class-wp-query.php:1639 — a search with no explicit
    # `orderby` ranks by match quality BEFORE the date order (:2562 prepends it):
    #   * one term: `post_title LIKE '%term%' DESC` — title matches first;
    #   * 2..6 terms: CASE — sentence-in-title(1), all-terms-in-title(2),
    #     any-term-in-title(3), sentence-in-excerpt(4), sentence-in-content(5), else 6;
    #   * 7+ terms: sentence matches only (the CASE keeps arms 1/4/5).
    # MySQL's LIKE is case-insensitive under the corpus collation, so ILIKE is the
    # faithful translation (RISK-007 sibling), and a boolean ordered DESC puts matches
    # first in both engines. The negative-query guard (`/(?:\s|^)\-/`) is transcribed:
    # a leading-minus term suppresses every sentence-match arm.
    def search_order_clause
      return nil if vars[:orderby].present?

      raw = vars[:s].presence || vars[:search].presence
      return nil if raw.blank?

      terms = self.class.search_terms(raw)
      return nil if terms.empty?

      title_likes = terms.map { |t| "posts.title ILIKE #{quote_like(t[:value])}" }
      return "#{title_likes.first} DESC" if terms.length == 1

      sentence = raw.match?(/(?:\s|^)-/) ? nil : quote_like(raw)
      arms = []
      arms << "WHEN posts.title ILIKE #{sentence} THEN 1" if sentence
      if terms.length < 7
        arms << "WHEN #{title_likes.join(" AND ")} THEN 2"
        arms << "WHEN #{title_likes.join(" OR ")} THEN 3"
      end
      if sentence
        arms << "WHEN posts.excerpt ILIKE #{sentence} THEN 4"
        arms << "WHEN posts.content ILIKE #{sentence} THEN 5"
      end
      return nil if arms.empty?

      "(CASE #{arms.join(" ")} ELSE 6 END)"
    end

    def quote_like(value)
      ActiveRecord::Base.connection.quote("%#{ActiveRecord::Base.sanitize_sql_like(value.to_s)}%")
    end

  end
end
