# frozen_string_literal: true

module Syndication
  # Wave 1. migration_strategy.md: feeds, sitemaps and embeds are "all terminal modules,
  # zero dependents (F-SIM-06). No write path. Proves deployment, replication and the diff
  # harness against real output at near-zero blast radius."
  #
  # The templates are byte-level transcriptions of wp-includes/feed-rss2.php,
  # feed-atom.php and feed-rss2-comments.php — whitespace included, because feeds are
  # not HTML: the diff harness compares them without whitespace collapsing.
  class FeedsController < ApplicationController
    include LegacyHeaders

    # The main feed query: published posts, newest first, `posts_per_rss` of them
    # (WP_Query `feed=rss2`; wp-includes/class-wp-query.php sets posts_per_page =
    # get_option('posts_per_rss')). `newest_first` is post_date DESC, the legacy's
    # unfiltered feed order.
    def show
      variant = params[:variant].presence || "rss2"
      @posts = Retrieval::PostQuery.new({ posts_per_page: posts_per_rss }).records.to_a
      @comment_counts = @posts.to_h { |p| [p.id, FeedText.comments_number(p)] }
      # get_feed_build_date('r'), wp-includes/feed.php:715 — the max post_modified_gmt
      # of the queried posts.
      @build_date = @posts.map(&:modified_at).compact.max || Time.current
      template = variant == "atom" ? "atom" : "rss2"
      render_with_legacy_content_type "syndication/feeds/#{template}", formats: [:xml],
                                      content_type: feed_content_type(template)
    end

    # /comments/feed/ — the site-wide comment feed. WP_Query with is_comment_feed:
    # approved comments of every type (comments, pingbacks, trackbacks — the golden
    # carries all three), comment_date_gmt DESC, posts_per_rss of them
    # (wp-includes/class-wp-query.php:3298, `get_comments` with 'orderby' =>
    # 'comment_date_gmt', 'order' => 'DESC', 'number' => posts_per_rss).
    # ⚠️ The post-status arm is the whole security of this endpoint (RISK-023 V3). The
    # legacy's comment-feed WHERE is, verbatim (class-wp-query.php:2833, the non-archive
    # non-search branch):
    #
    #   WHERE ( post_status = 'publish'
    #           OR ( post_status = 'inherit' AND post_type = 'attachment' ) )
    #     AND comment_approved = '1' AND comment_type != 'note'
    #
    # Filtering `comment_approved` ALONE — which is what this did — publishes the
    # discussion on every draft, pending, scheduled, trashed and private post to anonymous
    # visitors, and the feed prints each comment's post TITLE and permalink beside it. The
    # corpus happens to carry no comment on a non-public post, so the 53-screen comparison
    # never saw it: latent, not theoretical.
    #
    # Two arms of the legacy clause are unreachable here rather than omitted. There is no
    # `inherit` status in Post::STATUSES and an attachment is a Library::Asset, not a row
    # in `posts`, so no comment can hang off one (AGG-Comment belongs_to Publishing::Post);
    # and `note` is not among the kinds this system produces.
    def comments
      @comments = Discussion::Comment.where(status: "approved")
                                     .joins(:post).where(posts: { status: "published" })
                                     .order(submitted_at: :desc)
                                     .limit(posts_per_rss)
                                     .includes(:post)
                                     .to_a
      @parents = Discussion::Comment.where(id: @comments.map(&:parent_id).compact)
                                    .includes(:post).index_by(&:id)
      # get_feed_build_date on a comment feed folds the comment dates in with the
      # post modified times (feed.php:727-736).
      @build_date = (@comments.map(&:submitted_at) +
                     [Publishing::Post.visible.maximum(:modified_at)]).compact.max || Time.current
      render_with_legacy_content_type "syndication/feeds/comments", formats: [:xml],
                                      content_type: feed_content_type("rss2")
    end

    # ── Archive feeds ───────────────────────────────────────────────────────────────
    #
    # class-wp-rewrite.php:1150 appends a `feed/(feed|rdf|rss|rss2|atom)` endpoint to EVERY
    # permastruct, and `presentation/head.rb:235-248` duly prints those URLs in the <head>
    # of every archive the corpus renders. Nothing served them: the rebuild advertised 18
    # feed URLs and answered all 18 with its own 404 — the exact defect class bin/link_check
    # was built to find, and one a screen-content comparison can never see, because the PAGE
    # matched the oracle byte for byte while the links inside it were dead.
    #
    # A feed is not a different QUERY, it is a different RENDERER: template-loader.php
    # branches to do_feed() before the template hierarchy is consulted. So each action below
    # resolves its queried object exactly as Web::ArchivesController does and then renders
    # feed-rss2.php's transcription instead of a template.
    #
    # The two things that DO differ from the site feed:
    #   · the page size — WP_Query swaps posts_per_page for get_option('posts_per_rss')
    #   · `wp_title_rss()` resolves to wp_get_document_title() for the archive, which is
    #     why a category feed is titled "Uncategorized &#8211; <site>" and the site feed is
    #     titled "<site>". Presentation::DocumentTitle already computes exactly that string
    #     for the matching web screen, so the feed asks it rather than reimplementing it.
    def author
      user = Identity::User.find_by(login: params[:login])
      return not_found unless user

      archive_feed(build_feed_query(author: user.id), :author, author: user)
    end

    def category
      # A hierarchical path addresses the LEAF, as on the archive screen.
      slug = encoded(params[:path].to_s.split("/").last)
      term = find_term(slug, "category")
      return not_found unless term

      archive_feed(build_feed_query(category_name: slug), :category, term: term)
    end

    def tag
      slug = encoded(params[:slug])
      term = find_term(slug, "post_tag")
      return not_found unless term

      archive_feed(build_feed_query(tag: slug), :tag, term: term)
    end

    # `search/(.+)/feed/(feed|rdf|rss|rss2|atom)/?$`. The SCREEN is reached as `/?s=…`, but
    # the rewrite gives the feed a pretty URL and the head prints that form, so this route
    # exists even though its non-feed sibling does not.
    def search
      term = params[:term].to_s
      archive_feed(build_feed_query(s: term), :search, search_query: term)
    end

    # ── Comment feeds on a single record ────────────────────────────────────────────
    #
    # `<permalink>/feed/` is a COMMENT feed, not a post feed: WP_Query sets is_comment_feed
    # with is_singular and class-wp-query.php:3487 swaps the post loop for the comment one.
    # feed-rss2-comments.php then branches on is_singular() in three places — the channel
    # title ("Comments on: %s" vs "Comments for %s"), the channel link (the permalink vs the
    # site home) and each item's title ("By: %s" vs "Comment on %1$s by %2$s").
    def post_comments
      record = Publishing::Article.find_by(slug: encoded(params[:slug]))
      singular_comment_feed(record)
    end

    def page_comments
      singular_comment_feed(walk_page_path(params[:path].to_s))
    end

    private

    # Two query vars a feed sets differently from the screen it shadows:
    #
    #   · posts_per_page becomes get_option('posts_per_rss').
    #   · SEARCH RELEVANCE ORDERING IS SUPPRESSED. class-wp-query.php:2561 gates the
    #     relevance prefix on `empty($query_vars['orderby']) && ! $this->is_feed`, so a
    #     search FEED falls back to the default post_date DESC while the search SCREEN
    #     ranks by match quality. Confirmed on the oracle: /?s=article lists the matching
    #     post first, /search/article/feed/rss2/ lists Privacy Policy first — purely by
    #     date. Naming an `orderby` is how Retrieval::PostQuery's search_order_clause is
    #     suppressed (post_query.rb:250), and `date` is already its default column, so this
    #     changes nothing for a feed that was not searching.
    #
    # An explicit `?orderby=` still wins, exactly as the legacy's `empty()` test allows.
    def build_feed_query(**vars)
      merged = request.query_parameters.merge(vars)
      merged[:orderby] = "date" if merged[:orderby].blank? && merged["orderby"].blank?
      Retrieval::PostQuery.from_request(merged.merge(posts_per_page: posts_per_rss))
    end

    def archive_feed(query, kind, **facts)
      screen = Presentation::Screen.new(kind: kind, paged: query.page,
                                        found_posts: query.records.length, **facts)
      @posts = query.records.to_a
      @comment_counts = @posts.to_h { |p| [p.id, FeedText.comments_number(p)] }
      @build_date = @posts.map(&:modified_at).compact.max || Time.current
      @feed_title = Presentation::DocumentTitle.new(screen).to_s
      variant = params[:variant].presence || "rss2"
      template = variant == "atom" ? "atom" : "rss2"
      render_with_legacy_content_type "syndication/feeds/#{template}", formats: [:xml],
                                      content_type: feed_content_type(template)
    end

    def singular_comment_feed(record)
      return not_found if record.nil? || !record.status.to_s.eql?("published")

      @singular = record
      @comments = Discussion::Comment.where(status: "approved", post_id: record.id)
                                     .order(submitted_at: :desc)
                                     .limit(posts_per_rss)
                                     .includes(:post)
                                     .to_a
      @parents = Discussion::Comment.where(id: @comments.map(&:parent_id).compact)
                                    .includes(:post).index_by(&:id)
      @build_date = (@comments.map(&:submitted_at) + [record.modified_at]).compact.max || Time.current
      render_with_legacy_content_type "syndication/feeds/comments", formats: [:xml],
                                      content_type: feed_content_type("rss2")
    end

    # BR-MIGRATE-033: a page's slug is unique only within (type, parent), so the full path
    # is what disambiguates. The same walk Web::PagesController does, one segment at a time
    # against the scope the unique index enforces.
    def walk_page_path(path)
      segments = path.to_s.split("/").reject(&:empty?)
      return nil if segments.empty?

      parent_id = nil
      node = nil
      segments.each do |segment|
        node = Publishing::Page.where(status: %w[published], parent_id: parent_id)
                               .find_by(slug: segment)
        return nil if node.nil?

        parent_id = node.id
      end
      node
    end

    # utf8_uri_encode()'s output shape — the same re-encoding Web::ArchivesController,
    # Web::SingularController and Web::AttachmentsController each do, and for the same
    # reason: slugs are stored percent-encoded in lowercase hex and Rails hands the request
    # segment over decoded.
    def encoded(segment)
      segment.to_s.gsub(/[^\x00-\x7F]/) do |char|
        char.bytes.map { |byte| format("%%%02x", byte) }.join
      end
    end

    def find_term(slug, taxonomy)
      Classification::Term.joins(:taxonomy).find_by(slug: slug, taxonomies: { name: taxonomy })
    end

    def not_found
      render_screen(Presentation::Screen.new(kind: :not_found), status: :not_found)
    end

    # get_option('posts_per_rss'), default 10.
    def posts_per_rss
      (Configuration::Setting["posts_per_rss"].presence || 10).to_i
    end

    # feed_content_type(), wp-includes/feed.php:768, suffixed with the blog_charset
    # option exactly as feed-rss2.php:8 / feed-atom.php:13 / feed-rss2-comments.php:8 do.
    def feed_content_type(type)
      "#{type == "atom" ? "application/atom+xml" : "application/rss+xml"}; charset=#{blog_charset}"
    end
  end
end
