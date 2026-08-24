# frozen_string_literal: true

module Presentation
  # The MAIN query, with its conditional tags attached.
  #
  # In the legacy the loop's rows and the screen's conditional tags live on the SAME
  # object: `is_front_page()`, `get_queried_object()` and `have_posts()` are all reads of
  # the global `$wp_query`. The controller here builds the two halves separately — a
  # Retrieval::PostQuery for the rows, a Presentation::Screen for the facts — and this
  # delegator reunites them so `ctx.query` answers both, exactly as `$wp_query` did.
  #
  # Why not context keys alone: `Composition::RenderContext#context` is BLOCK context,
  # and the navigation family faithfully REPLACES it for its children (WP_Block_List's
  # `$available_context`, navigation_blocks.rb `child_context`). The conditional tags are
  # not block context in the legacy — page-list.php:283 calls the global
  # `get_queried_object_id()` from arbitrarily deep inside a navigation — so they must
  # ride on the field that survives that replacement, which is `query`.
  class MainQuery < SimpleDelegator
    def initialize(query, screen)
      super(query)
      @screen = screen
    end

    # The conditional tags Composition::Renderers::PostBlocks::Screen names
    # (post_blocks.rb:44), answered by the controller's Screen.
    def archive? = @screen.archive?
    def search? = @screen.search?
    def front_page? = @screen.front_page?
    def home? = @screen.home?
    def paged? = @screen.paged?
    def singular? = @screen.singular?

    # get_search_query() — the raw term; callers escape at the call site.
    def search_query = @screen.search_query.to_s

    # get_queried_object(). For a DATE archive the legacy's queried object is null and
    # get_the_archive_title() reads `get_query_var('year'/'monthnum'/'day')` instead
    # (general-template.php:1808); the renderers take those three facts as one Hash —
    # the shape post_blocks.rb:71 documents.
    def queried_object
      if @screen.date?
        return { "year" => @screen.year, "monthnum" => @screen.month, "day" => @screen.day }
      end

      @screen.queried_object
    end
  end
end
