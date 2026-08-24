# frozen_string_literal: true

module PublicApi
  # WP_REST_Autosaves_Controller::prepare_item_for_response(), which is
  # WP_REST_Revisions_Controller's with `preview_link` added
  # (class-wp-rest-autosaves-controller.php:376).
  #
  # An autosave is served in EDIT context always — the controller forces it (":260,
  # `$request->set_param( 'context', 'edit' )`") — so `raw` is present on every text field
  # and there is no view/embed variant to build. What is NOT present is the posts
  # controller's `protected` / `block_version` / status / class_list family: a revision
  # has no permalink, no terms and no post class.
  #
  # ⚠️ TWO SHAPES, one endpoint, and the difference is load-bearing for the editor:
  #   · a real autosave revision  -> `id` is the REVISION's, `parent` the post's, and the
  #                                  `_links.parent` link is present;
  #   · a draft the caller owns   -> the autosave WAS the post (see AutosavesController),
  #                                  so `id` is the POST's, `parent` is 0 — and because
  #                                  WP_REST_Revisions_Controller only adds the parent
  #                                  link `if ( ! empty( $data['parent'] ) )`, there are
  #                                  NO `_links` at all. The oracle confirms both.
  class AutosaveSerializer
    include Entity

    # `_wp_post_revision_data()` names an autosave `{parent}-autosave-v1`
    # (wp-includes/revision.php); a regular revision is `{parent}-revision-v1`.
    def initialize(record, post:)
      @record = record
      @post = post
    end

    def self.collection(records, post:) = records.map { |r| new(r, post: post).as_json }

    def as_json
      json = {
        author: author_id,
        date: iso(instant),
        date_gmt: iso(instant),
        id: id,
        modified: iso(modified_instant),
        modified_gmt: iso(modified_instant),
        parent: parent_id,
        slug: slug,
        guid: { rendered: guid, raw: guid },
        title: { raw: record.title.to_s, rendered: rendered_title },
        content: { raw: record.content.to_s, rendered: rendered_content },
        excerpt: { raw: record.excerpt.to_s, rendered: rendered_excerpt },
        meta: { footnotes: "" },
        preview_link: preview_link
      }
      json[:_links] = { parent: [{ href: Url.rest("/wp/v2/#{rest_base}/#{parent_id}") }] } if parent_id.positive?
      json
    end

    private

    attr_reader :record, :post

    # The two shapes. `record` is either a Publishing::Revision or the post itself.
    def revision? = record.is_a?(Publishing::Revision)

    def id = record.id
    def parent_id = revision? ? post.id : 0
    def author_id = (revision? ? record.author_id : post.author_id).to_i
    def rest_base = post.is_a?(Publishing::Page) ? "pages" : "posts"
    def slug = revision? ? "#{post.id}-autosave-v1" : post.slug.to_s

    # A revision row carries no publication instant of its own; the legacy's post_date on
    # a revision is when the snapshot was taken. AD-07 keeps one instant, `created_at`.
    def instant = revision? ? record.created_at : post.published_at
    def modified_instant = revision? ? record.created_at : (post.modified_at || post.published_at)

    def guid = "#{Entity.site.home_url}/?p=#{id}"

    def rendered_title
      Entity.text.capital_p_title(
        Entity.text.convert_chars(Entity.text.wptexturize(record.title.to_s)).strip
      )
    end

    # The revisions controller renders through `the_content` / `the_excerpt` on the
    # REVISION's own fields, with no post context — so the block renderer is not involved
    # and the filters reduce to wpautop over the stored markup.
    def rendered_content
      body = record.content.to_s
      body.empty? ? "" : Entity.text.wpautop(Entity.text.convert_chars(Entity.text.wptexturize(body)))
    end

    def rendered_excerpt
      body = record.excerpt.to_s
      body.empty? ? "" : Entity.text.wpautop(Entity.text.convert_chars(Entity.text.wptexturize(body)))
    end

    # get_preview_post_link() (wp-includes/link-template.php:4001).
    #
    #   · the draft-in-place arm previews the POST itself: `?preview=true` on its permalink,
    #     which for a draft is the plain `?p=<id>`;
    #   · an autosave revision previews the PARENT with the revision's content swapped in,
    #     which the front end can only do if it can prove the request came from the editor
    #     — hence `preview_id` + `preview_nonce`, the nonce being `post_preview_<parent id>`
    #     (Identity::Nonce, the same family as the REST nonce).
    def preview_link
      permalink = Entity.links.permalink(post).presence || "#{Entity.site.home_url}/?p=#{post.id}"
      return append_query(permalink, "preview" => "true") unless revision?

      append_query(permalink,
                   "preview_id" => post.id.to_s,
                   "preview_nonce" => Identity::Nonce.issue("post_preview_#{post.id}"),
                   "preview" => "true")
    end

    # add_query_arg(): appends in the given order, with `?` or `&` as the URL requires.
    def append_query(url, pairs)
      separator = url.include?("?") ? "&" : "?"
      "#{url}#{separator}#{pairs.map { |k, v| "#{k}=#{v}" }.join("&")}"
    end
  end
end
