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

    private

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
