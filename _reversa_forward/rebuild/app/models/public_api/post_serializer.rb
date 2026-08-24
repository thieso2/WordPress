# frozen_string_literal: true

module PublicApi
  # WP_REST_Posts_Controller::prepare_item_for_response(), for the `post` and `page`
  # subtypes (wp-includes/rest-api/endpoints/class-wp-rest-posts-controller.php:1900).
  # Every rendered field is produced through the same ports the front-end renders with,
  # so a value here is byte-identical to the same post on a golden page.
  class PostSerializer
    include Entity

    def initialize(post)
      @post = post
      @page = post.is_a?(Publishing::Page)
      @attachment = false
    end

    def self.collection(posts) = posts.map { |p| new(p).as_json }

    def as_json
      json = base
      if @page
        json[:parent] = @post.parent_id.to_i
        json[:menu_order] = @post.menu_order.to_i
        json[:comment_status] = @post.comment_status.to_s
        json[:ping_status] = "open"
        json[:template] = @post.template_slug.to_s
        json[:meta] = { footnotes: "" }
        json[:class_list] = class_list
      else
        json[:comment_status] = @post.comment_status.to_s
        json[:ping_status] = "open"
        json[:sticky] = sticky?
        json[:template] = @post.template_slug.to_s
        json[:format] = "standard"
        json[:meta] = { footnotes: "" }
        json[:categories] = term_ids("category")
        json[:tags] = term_ids("post_tag")
        json[:class_list] = class_list
      end
      json[:_links] = links_for
      json
    end

    private

    attr_reader :post

    def rest_base = @page ? "pages" : "posts"
    def type_slug = @page ? "page" : "post"

    def base
      ctx = Composition::RenderContext.new(post: post)
      {
        id: post.id,
        date: iso(post.published_at),
        date_gmt: iso(post.published_at),
        guid: { rendered: guid },
        modified: iso(post.modified_at || post.published_at),
        modified_gmt: iso(post.modified_at || post.published_at),
        slug: post.slug.to_s,
        status: rest_status,
        type: type_slug,
        link: Entity.links.permalink(post),
        title: { rendered: rest_title },
        # `post_password_required($post) ? '' : the_content`, and `protected` is
        # `(bool) $post->post_password` regardless of the cookie
        # (class-wp-rest-posts-controller.php:2050). No postpass cookie exists on this
        # surface, so a protected body is always blanked.
        content: { rendered: protected? ? "" : Entity.text.the_content(post, ctx),
                   protected: protected? },
        excerpt: { rendered: protected? ? "" : rest_excerpt(ctx), protected: protected? },
        author: post.author_id.to_i,
        featured_media: post.featured_asset_id.to_i
      }
    end

    # WP_REST_Posts_Controller filters `protected_title_format` to '%s' while preparing
    # the title (:1961), so the REST title carries NO "Protected:"/"Private:" prefix — it
    # is `the_title` minus the two prefix arms Text.the_title adds for the front end.
    def rest_title
      Entity.text.capital_p_title(Entity.text.convert_chars(Entity.text.wptexturize(post.title.to_s)).strip)
    end

    def protected? = post.respond_to?(:password_digest) && post.password_digest.present?

    # post_status -> REST status. The one rename is `published` -> `publish` (AD-02 keeps
    # the legacy vocabulary internally); the rest already match.
    def rest_status
      { "published" => "publish" }.fetch(post.status.to_s, post.status.to_s)
    end

    # get_the_guid(): the legacy stores `?p=<id>` / `?page_id=<id>`; AD-03 stores a UUID in
    # the column instead, so the REST guid is regenerated in the legacy's shape, which is
    # also what the oracle emits.
    def guid
      key = @page ? "page_id" : "p"
      "#{Entity.site.home_url}/?#{key}=#{post.id}"
    end

    # get_the_excerpt() -> wp_trim_excerpt() then the `the_excerpt` filter (wpautop). A
    # manual excerpt is used verbatim; otherwise the rendered content is trimmed to 55
    # words with ' [&hellip;]'. Matches the oracle byte-for-byte (probe: posts 1 and 2).
    def rest_excerpt(ctx)
      stored = post.excerpt.to_s
      base = if stored.strip.empty?
               rendered = Entity.text.the_content(post, ctx)
               return "" if rendered.empty?

               Entity.text.trim_words(rendered, 55, " [&hellip;]")
             else
               stored
             end
      Entity.text.wpautop(Entity.text.convert_chars(Entity.text.wptexturize(base)))
    end

    def sticky?
      # `get_option('sticky_posts')` is an array of ids, but `false` when unset — and
      # Array(false) is [false], not [], so guard the type before mapping to ids.
      list = Configuration::Setting["sticky_posts"]
      list = [] unless list.is_a?(Array)
      list.map(&:to_i).include?(post.id)
    end

    # wp_get_object_terms(id, taxonomy, fields: ids) — default orderby name ASC.
    def term_ids(taxonomy)
      object_terms(taxonomy).map(&:id)
    end

    def object_terms(taxonomy)
      (@object_terms ||= Classification::Assignment
        .where(classifiable_type: "Publishing::Post", classifiable_id: post.id)
        .includes(term: :taxonomy).map(&:term))
        .select { |t| t.taxonomy&.name == taxonomy }
        .sort_by(&:name)
    end

    # get_post_class(), wp-includes/post-template.php:625 — the arms this corpus reaches,
    # in source order.
    def class_list
      classes = ["post-#{post.id}", type_slug, "type-#{type_slug}", "status-#{rest_status}"]
      classes << "format-standard" unless @page || @attachment
      # post-template.php:672 — password class, then thumbnail, then hentry. No postpass
      # cookie exists here, so a passworded post is always `post-password-required`.
      classes << "post-password-required" if protected?
      classes << "has-post-thumbnail" if post.respond_to?(:featured_asset_id) && post.featured_asset_id.present?
      classes << "hentry"
      unless @page || @attachment
        object_terms("category").each do |t|
          classes << sanitize_html_class("category-#{sanitize_html_class(t.slug, t.id)}")
        end
        object_terms("post_tag").each do |t|
          tc = sanitize_html_class(t.slug, t.id)
          tc = t.id.to_s if tc.match?(/\A-?\d+\z/) || tc.delete("-").empty?
          classes << "tag-#{tc}"
        end
      end
      classes
    end

    def links_for
      base_href = Url.rest("/wp/v2/#{rest_base}")
      out = {
        self: [{ href: "#{base_href}/#{post.id}", targetHints: { allow: %w[GET] } }],
        collection: [{ href: base_href }],
        about: [{ href: Url.rest("/wp/v2/types/#{type_slug}") }]
      }
      out[:author] = [{ embeddable: true, href: Url.rest("/wp/v2/users/#{post.author_id}") }] if post.author_id.present?
      out[:replies] = [{ embeddable: true, href: Url.rest("/wp/v2/comments?post=#{post.id}") }]
      revcount = post.revisions.count
      out[:"version-history"] = [{ count: revcount, href: "#{base_href}/#{post.id}/revisions" }]
      if revcount.positive?
        out[:"predecessor-version"] = [{ id: post.revisions.maximum(:id),
                                         href: "#{base_href}/#{post.id}/revisions/#{post.revisions.maximum(:id)}" }]
      end
      if !@page && post.featured_asset_id.present?
        out[:"wp:featuredmedia"] = [{ embeddable: true, href: Url.rest("/wp/v2/media/#{post.featured_asset_id}") }]
      end
      out[:"wp:attachment"] = [{ href: Url.rest("/wp/v2/media?parent=#{post.id}") }]
      unless @page
        out[:"wp:term"] = [
          { taxonomy: "category", embeddable: true, href: Url.rest("/wp/v2/categories?post=#{post.id}") },
          { taxonomy: "post_tag", embeddable: true, href: Url.rest("/wp/v2/tags?post=#{post.id}") }
        ]
      end
      out[:curies] = Entity.curies
      out
    end
  end
end
