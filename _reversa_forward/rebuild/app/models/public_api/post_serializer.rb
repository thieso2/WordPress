# frozen_string_literal: true

module PublicApi
  # WP_REST_Posts_Controller::prepare_item_for_response(), for the `post` and `page`
  # subtypes (wp-includes/rest-api/endpoints/class-wp-rest-posts-controller.php:1900).
  # Every rendered field is produced through the same ports the front-end renders with,
  # so a value here is byte-identical to the same post on a golden page.
  class PostSerializer
    include Entity

    # `context` is the request's (view|embed|edit) and `caps` is what the CONTROLLER
    # decided about this actor and this record (PublicApi::PostCapabilities) — the
    # serialiser never touches Access itself (BR-CAP-05 / target_architecture.md Note 2).
    def initialize(post, context: "view", caps: PublicApi::PostCapabilities.none)
      @post = post
      @page = post.is_a?(Publishing::Page)
      @attachment = false
      @context = context.to_s
      @caps = caps
    end

    def self.collection(posts, **options) = posts.map { |p| new(p, **options).as_json }

    # filter_response_by_context() (class-wp-rest-controller.php:487): the FULL item is
    # prepared once and then reduced to the fields whose schema lists this context. Every
    # key below therefore appears in the legacy's own order, and the context decides which
    # survive — which is why `_fields` (PublicApi::FieldFilter) can intersect the result
    # without knowing anything about contexts.
    #
    # The three sets, transcribed from the schema's `context` arrays and re-verified
    # key-for-key against the live oracle (/wp/v2/posts/1 in all three contexts, and
    # /wp/v2/pages?context=edit for the hierarchical variant).
    VIEW_FIELDS = %i[
      id date date_gmt guid modified modified_gmt slug status type link title content
      excerpt author featured_media parent menu_order comment_status ping_status sticky
      template format meta categories tags class_list
    ].freeze

    EMBED_FIELDS = %i[id date slug type link title excerpt author featured_media].freeze

    # `password`, `permalink_template` and `generated_slug` are edit-only; the rest of the
    # difference is inside the sub-objects (raw, block_version). Spelled out rather than
    # appended, because their POSITION is observable: `password` sits between modified_gmt
    # and slug, and the two permalink fields between tags and class_list.
    EDIT_FIELDS = %i[
      id date date_gmt guid modified modified_gmt password slug status type link title
      content excerpt author featured_media parent menu_order comment_status ping_status
      sticky template format meta categories tags permalink_template generated_slug
      class_list
    ].freeze

    def edit? = @context == "edit"
    def embed? = @context == "embed"

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
      json = json.slice(*context_fields)
      json[:_links] = links_for
      json
    end

    def context_fields
      case @context
      when "edit"  then EDIT_FIELDS
      when "embed" then EMBED_FIELDS
      else VIEW_FIELDS
      end
    end

    private

    attr_reader :post

    def rest_base = @page ? "pages" : "posts"
    def type_slug = @page ? "page" : "post"

    def base
      ctx = Composition::RenderContext.new(post: post)
      json = {
        id: post.id,
        date: iso(post.published_at),
        date_gmt: iso(post.published_at),
        guid: guid_field,
        modified: iso(post.modified_at || post.published_at),
        modified_gmt: iso(post.modified_at || post.published_at),
        slug: post.slug.to_s,
        status: rest_status,
        type: type_slug,
        link: rest_link,
        title: title_field,
        # `post_password_required($post) ? '' : the_content`, and `protected` is
        # `(bool) $post->post_password` regardless of the cookie
        # (class-wp-rest-posts-controller.php:2050). No postpass cookie exists on this
        # surface, so a protected body is always blanked.
        content: content_field(ctx),
        excerpt: excerpt_field(ctx),
        author: post.author_id.to_i,
        featured_media: post.featured_asset_id.to_i
      }
      return json unless edit?

      # ⚠️ RECORDED DIVERGENCE. The legacy returns `$post->post_password` — the plaintext,
      # because wp_posts stores it in the clear. AD-05 / the target schema store a BCRYPT
      # DIGEST (`posts.password_digest`), which is one-way by construction, so the
      # plaintext cannot be returned and this field is always the empty string. The
      # observable consequence is confined to the editor's "Password protected" control,
      # which reads a blank where the legacy shows the password; `content.protected` and
      # the blanked body (above) are unaffected, so every READER sees exactly what the
      # legacy shows. See the parity report.
      json[:password] = ""
      json[:permalink_template] = permalink_template
      json[:generated_slug] = generated_slug
      json
    end

    # `guid` is `{rendered}` everywhere and gains `raw` in edit context — both are the
    # same string (the schema marks `raw` readonly).
    def guid_field
      value = guid
      edit? ? { rendered: value, raw: value } : { rendered: value }
    end

    def title_field
      rendered = { rendered: rest_title }
      edit? ? { raw: post.title.to_s }.merge(rendered) : rendered
    end

    def content_field(ctx)
      json = { rendered: protected? ? "" : Entity.text.the_content(post, ctx), protected: protected? }
      return json unless edit?

      # block_version() (wp-includes/blocks.php): 1 when the stored markup contains a
      # block delimiter, 0 when it is classic HTML. has_blocks() is `str_contains( '<!-- wp:' )`
      # and nothing more.
      { raw: post.content.to_s }.merge(json).merge(block_version: block_version)
    end

    def excerpt_field(ctx)
      json = { rendered: protected? ? "" : rest_excerpt(ctx), protected: protected? }
      edit? ? { raw: post.excerpt.to_s }.merge(json) : json
    end

    def block_version = post.content.to_s.include?("<!-- wp:") ? 1 : 0

    # get_permalink() for a record that has no pretty URL yet — a draft, a pending or a
    # trashed record — is the PLAIN permalink, `?p=<id>` (`?page_id=<id>` for a page),
    # which is also what `guid` prints. Entity.links.permalink answers "" for those, so
    # the plain form is supplied here rather than changing the front-end port.
    def rest_link
      pretty = Entity.links.permalink(post)
      pretty.presence || guid
    end

    # get_sample_permalink() (wp-admin/includes/post.php:1449), the pair the editor's
    # permalink control is built from: [template, generated slug].
    #
    # The function temporarily republishes a draft so the PRETTY structure is used
    # (`in_array( $post->post_status, array( 'draft', 'pending', 'future', 'auto-draft' ) )`)
    # — note `trash` is NOT in that list, which is why a trashed record's template is the
    # plain `?p=<id>`, as the oracle confirms.
    def permalink_template
      return guid if post.trashed?
      return "#{Entity.site.home_url}/#{page_ancestor_path}%pagename%/" if @page

      at = post.published_at || post.created_at || Time.current
      "#{Entity.site.home_url}/#{at.in_time_zone(Entity.site.timezone).strftime("%Y/%m")}/%postname%/"
    end

    def page_ancestor_path
      segments = []
      node = post.parent
      seen = Set.new
      while node && !seen.include?(node.id)
        seen << node.id
        segments.unshift(node.slug)
        node = node.parent
      end
      segments.compact.any? ? "#{segments.compact.join("/")}/" : ""
    end

    # `wp_unique_post_slug( sanitize_title( $post->post_title ), ... )` — derived from the
    # TITLE and ignoring the slug the record already carries, which is what makes it the
    # "generated" slug the editor offers when you clear the field. Routing owns uniqueness
    # (BR-MIGRATE-033/034) and already excludes the record itself.
    def generated_slug
      Routing::SlugAllocator.new.allocate(post, requested: post.title.to_s).to_s
    end

    # WP_REST_Posts_Controller filters `protected_title_format` to '%s' while preparing
    # the title (:1961), so the REST title carries NO "Protected:"/"Private:" prefix — it
    # is `the_title` minus the two prefix arms Text.the_title adds for the front end.
    def rest_title
      Entity.text.capital_p_title(Entity.text.convert_chars(Entity.text.wptexturize(post.title.to_s)).strip)
    end

    def protected? = post.respond_to?(:password_digest) && post.password_digest.present?

    # post_status -> REST status. AD-02 keeps the legacy VOCABULARY internally but not the
    # legacy SPELLING, so four of the seven statuses are renamed on the way out. The full
    # map, not just `published`: the write surface can now put a record into `scheduled`
    # and `trashed`, and the editor keys its whole save/schedule/trash UI off these exact
    # strings (`future` and `trash` are what @wordpress/editor looks for).
    STATUS_NAMES = {
      "published" => "publish", "scheduled" => "future",
      "trashed" => "trash", "auto_draft" => "auto-draft"
    }.freeze

    def rest_status
      STATUS_NAMES.fetch(post.status.to_s, post.status.to_s)
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
        # class-wp-rest-server.php's target hints: the verbs THIS caller may use on the
        # record. Anonymous -> ["GET"]; an editor of it -> GET, POST, PUT, PATCH, DELETE.
        self: [{ href: "#{base_href}/#{post.id}", targetHints: { allow: @caps.allowed_methods } }],
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
      # :2277 — a hierarchical type with a parent links `up` to it.
      if @page && post.parent_id.present?
        out[:up] = [{ embeddable: true, href: Url.rest("/wp/v2/pages/#{post.parent_id}") }]
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
      action_rels.each { |rel| out[rel] = [{ href: "#{base_href}/#{post.id}" }] }
      out[:curies] = Entity.curies
      out
    end

    # get_available_actions(), class-wp-rest-posts-controller.php:2341. EDIT CONTEXT ONLY
    # (":2346, if ( 'edit' !== $request['context'] ) return array()"), one rel per
    # capability the caller holds, in the source's own order. Gutenberg reads these to
    # decide whether to offer the Publish button, the sticky toggle, the author picker and
    # the "create a new category" affordance — so they are part of the boot contract, not
    # decoration. The capability answers were decided by the controller (PostCapabilities).
    def action_rels
      return [] unless edit?

      rels = []
      rels << :"wp:action-publish" if @caps.publish
      rels << :"wp:action-unfiltered-html" if @caps.unfiltered_html
      # :2360 — `sticky` is a `post`-only action, and needs BOTH edit_others_posts and
      # publish_posts.
      rels << :"wp:action-sticky" if !@page && @caps.edit_others && @caps.publish
      rels << :"wp:action-assign-author" if @caps.edit_others
      unless @page
        rels << :"wp:action-create-categories" if @caps.create_categories
        rels << :"wp:action-assign-categories" if @caps.assign_categories
        rels << :"wp:action-create-tags" if @caps.create_tags
        rels << :"wp:action-assign-tags" if @caps.assign_tags
      end
      rels
    end
  end
end
