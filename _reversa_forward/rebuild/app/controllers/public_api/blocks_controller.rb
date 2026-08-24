# frozen_string_literal: true

module PublicApi
  # /wp/v2/blocks — WP_REST_Blocks_Controller, the REUSABLE BLOCKS (`wp_block`).
  #
  # ⚠️ AD-02 split `wp_block` out of `wp_posts` into `patterns`, which is the same table
  # the THEME's registered block patterns are loaded into (`rake theme:load`). Those are
  # not reusable blocks and must never appear here: the legacy keeps them in a registry,
  # not in the posts table, and `/wp/v2/blocks` would be answering with 98 rows nobody
  # created. The two are told apart by the shape of the slug, which is not a heuristic but
  # a property of where each came from — a registered pattern's name is NAMESPACED
  # (`twentytwentyfive/hero`, WP_Block_Patterns_Registry requires the `<namespace>/<slug>`
  # form), while a reusable block's slug is a `post_name`, and sanitize_title() strips the
  # slash. So a slug containing `/` is a registered pattern and nothing else can be.
  #
  # ⚠️ The three fields the `patterns` table cannot answer, stated rather than faked:
  # a `wp_block` post's own `post_status`, its `wp_pattern_category` terms and its
  # `wp_pattern_sync_status` meta were not carried across by the seeding pipeline
  # (lib/seeding/pipeline.rb:726 keeps slug, title, content and the modified stamp). They
  # are emitted as the values every row in this corpus actually has — `publish`, `[]` and
  # `""` — which is what the oracle returns for its one reusable block. A rebuild that
  # starts writing these needs columns first; this endpoint is the reader, not the reason.
  #
  # Permission: none on the collection (BR-REST-05). `wp_block` is not a public post type,
  # so the legacy's per-record read check is what empties the list for an anonymous
  # caller — verified against the oracle, which answers `[]` with a 200 and X-WP-Total: 0.
  class BlocksController < BaseController
    include CollectionPagination

    permission :show, :read_item

    def index
      scope = readable_scope
      total = scope.count
      records = scope.order(:id).offset((page_param - 1) * per_page_param).limit(per_page_param).to_a
      set_pagination_headers(total: total, base_path: "/wp/v2/blocks")
      render_json(records.map { |p| serialize(p) })
    end

    def show
      render_json(serialize(loaded_pattern))
    end

    private

    # `wp_block` posts are readable only by someone who can edit posts — the post type is
    # registered with `public => false` (wp-includes/post.php's register_post_type).
    def can_read? = current_actor && Access::SitePolicy.new(current_actor, nil).permit?(:edit_posts)

    def readable_scope
      return Composition::Pattern.none unless can_read?

      Composition::Pattern.where.not("slug LIKE '%/%'")
    end

    def read_item
      loaded_pattern
      can_read?
    end

    def loaded_pattern
      @loaded_pattern ||= Composition::Pattern.where.not("slug LIKE '%/%'").find_by(id: params[:id]) ||
                          raise(PublicApi::RestError.new("rest_post_invalid_id", "Invalid post ID.", 404))
    end

    # WP_REST_Blocks_Controller inherits WP_REST_Posts_Controller's shape and overrides the
    # schema so `title` and `content` expose `raw` in VIEW context too — a reusable block
    # is edited, never rendered as a page, so the raw markup is the point.
    def serialize(pattern)
      stamp = Entity.iso(pattern.updated_at)
      {
        id: pattern.id,
        date: stamp,
        date_gmt: stamp,
        guid: { rendered: "#{Url.home}/?p=#{pattern.id}" },
        modified: stamp,
        modified_gmt: stamp,
        slug: pattern.slug.to_s,
        status: "publish",
        type: "wp_block",
        link: link_for(pattern),
        title: { raw: pattern.title.to_s },
        content: { raw: pattern.content.to_s, protected: false },
        excerpt: { rendered: excerpt_for(pattern), protected: false },
        template: "",
        meta: { footnotes: "" },
        wp_pattern_category: [],
        wp_pattern_sync_status: "",
        _links: links(pattern)
      }
    end

    # get_the_excerpt() -> wp_trim_excerpt(): a reusable block has no stored excerpt, so
    # the rendered content is trimmed to 55 words and wpautop'd — the same pipeline
    # PublicApi::PostSerializer#rest_excerpt runs, through the same ports, so the two
    # agree by construction. The content is rendered rather than tag-stripped because a
    # reusable block may hold dynamic blocks whose text does not exist until they render.
    def excerpt_for(pattern)
      rendered = Composition::Renderer.render(
        Composition::Parser.parse(pattern.content.to_s), Composition::RenderContext.new
      )
      return "" if rendered.to_s.empty?

      base = Entity.text.trim_words(rendered, 55, " [&hellip;]")
      Entity.text.wpautop(Entity.text.convert_chars(Entity.text.wptexturize(base)))
    end

    # The corpus's permalink structure is `/%year%/%monthnum%/%postname%/`
    # (Routing::PermalinkStructure::DEFAULT_PATTERN), and the timestamp the pipeline kept
    # is `post_modified_gmt`. Same construction as the front end's
    # Composition::Renderers::PostBlocks::Links#permalink, against the site timezone.
    def link_for(pattern)
      return "#{Url.home}/?p=#{pattern.id}" if pattern.slug.blank? || pattern.updated_at.nil?

      local = pattern.updated_at.in_time_zone(Configuration::Setting["timezone_string"].presence || "UTC")
      "#{Url.home}/#{local.strftime("%Y/%m")}/#{pattern.slug}/"
    end

    def links(pattern)
      self_href = Url.rest("/wp/v2/blocks/#{pattern.id}")
      {
        self: [{ href: self_href, targetHints: { allow: %w[GET POST PUT PATCH DELETE] } }],
        collection: [{ href: Url.rest("/wp/v2/blocks") }],
        about: [{ href: Url.rest("/wp/v2/types/wp_block") }],
        "version-history": [{ count: 0, href: "#{self_href}/revisions" }],
        "wp:attachment": [{ href: Url.rest("/wp/v2/media?parent=#{pattern.id}") }],
        "wp:term": [{ taxonomy: "wp_pattern_category", embeddable: true,
                      href: Url.rest("/wp/v2/wp_pattern_category?post=#{pattern.id}") }],
        curies: Entity.curies
      }
    end
  end
end
