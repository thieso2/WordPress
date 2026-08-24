# frozen_string_literal: true

module PublicApi
  # WP_REST_Attachments_Controller::prepare_item_for_response()
  # (wp-includes/rest-api/endpoints/class-wp-rest-attachments-controller.php:660). It
  # extends the posts response with the attachment-specific fields (alt_text,
  # media_type, mime_type, media_details, source_url, filename, filesize).
  #
  # `context` is the request's own (view|embed|edit). In `edit` every rendered field
  # gains its `raw` sibling and the editor-only fields appear — that is the context the
  # REST server forces on a create/update response (`$request->set_param('context','edit')`,
  # :1099), which is why the write path needs it.
  #
  # `allow` is the method list the CONTROLLER computed for this actor+record and is
  # emitted as `_links.self[0].targetHints.allow` — rest_send_allow_header()'s value.
  # Access is deliberately NOT reached from here (BR-CAP-05: the controller is the only
  # layer that touches Access), so the answer arrives already decided.
  #
  # ⚠️ VALUE-PARITY LIMITATION (reported, not faked). The Library::Asset aggregate
  # (owned by the media track) is a SEPARATE table from posts, so:
  #   * `id` is the asset's own id (1..), not the shared wp_posts id (26..) the oracle
  #     emits — attachments do not live in the post id-space here (AGG-Asset ruling).
  #   * `date`/`modified` are the row's created/updated timestamps (the seed did not
  #     preserve the legacy post_date).
  #   * there is NO post_content column, so `description.rendered` carries only the
  #     `prepend_attachment` image markup, never the description prose the oracle shows,
  #     and `description.raw` is always empty.
  # The SHAPE and the derivable fields (media_details from `metadata`, source_url, the
  # size table, image_meta) are faithful; the identity fields above cannot be without a
  # cross-track schema change. See the handoff report.
  class MediaSerializer
    include Entity

    UPLOADS = "/wp-content/uploads"

    # The `Allow`/targetHints value for a caller with no write rights.
    READ_ONLY = %w[GET].freeze

    # wp_editor_set_quality()'s default (wp-includes/class-wp-image-editor.php:322) and
    # the two 7.2 image-pipeline fields that are settings-shaped, not per-asset. AD-06:
    # they are configuration, and nothing in this corpus moves them off the default, so
    # they are stated here rather than stored per row.
    DEFAULT_IMAGE_QUALITY = 82

    def initialize(asset, context: "view", allow: READ_ONLY, actions: [])
      @asset = asset
      @context = context.to_s
      @allow = Array(allow)
      @actions = Array(actions)
    end

    def self.collection(assets, context: "view", allow: READ_ONLY, actions: [])
      assets.map { |a| new(a, context: context, allow: allow, actions: actions).as_json }
    end

    def edit? = @context == "edit"

    def as_json
      json = {
        id: asset.id,
        date: iso(asset.created_at),
        date_gmt: iso(asset.created_at),
        guid: guid_field,
        modified: iso(asset.updated_at || asset.created_at),
        modified_gmt: iso(asset.updated_at || asset.created_at),
        slug: asset.slug.to_s,
        status: "inherit",
        type: "attachment",
        link: attachment_link,
        title: raw_and_rendered(asset.title.to_s, rendered_title),
        author: asset.uploader_id.to_i,
        featured_media: 0,
        comment_status: "open",
        ping_status: "closed",
        template: "",
        meta: []
      }
      if edit?
        # class-wp-rest-posts-controller.php:1836/:1846 — both are edit-context only.
        json[:permalink_template] = "#{Entity.site.home_url}/?attachment_id=#{asset.id}"
        json[:generated_slug] = Sanitizing::Formatting.sanitize_title(asset.title.to_s)
      end
      json[:class_list] = %W[post-#{asset.id} attachment type-attachment status-inherit hentry]
      # AGG-Asset has no post_content column, so the raw description is always empty.
      json[:description] = raw_and_rendered("", rendered_description)
      json[:caption] = raw_and_rendered(asset.caption.to_s, rendered_caption)
      json[:alt_text] = asset.alt_text.to_s
      json[:media_type] = image? ? "image" : "file"
      json[:mime_type] = asset.mime_type.to_s
      json[:media_details] = media_details
      # ⚠️ `post` is NULL, not 0, for an unattached asset — verified against the oracle
      # (`/wp/v2/media/<unattached>` answers `"post": null`).
      json[:post] = asset.attached_to_id.present? ? asset.attached_to_id.to_i : nil
      json[:source_url] = source_url
      if edit?
        # class-wp-rest-attachments-controller.php:820 — every registered size the
        # metadata does not carry. Library::Asset generates them all up front, so this
        # is empty unless the editor refused a size.
        json[:missing_image_sizes] = missing_image_sizes
      end
      json[:filename] = File.basename(relative_file)
      json[:filesize] = asset.byte_size.to_i
      if edit?
        json[:exif_orientation] = exif_orientation
        json[:image_output_format] = nil
        json[:image_save_progressive] = false
        json[:image_quality] = { default: DEFAULT_IMAGE_QUALITY, sizes: [] }
      end
      json[:_links] = links_for
      json
    end

    private

    attr_reader :asset

    # `view`/`embed` print only the rendered value; `edit` adds `raw` (the field's
    # `context` array in the schema, class-wp-rest-posts-controller.php:2400). The key
    # ORDER differs per field in the legacy's own output — `guid` emits rendered first,
    # `title`/`description`/`caption` emit raw first — because prepare_item_for_response
    # builds each one in a different order (:1010 vs :1030). Reproduced.
    def raw_and_rendered(raw, rendered)
      return { rendered: rendered } unless edit?

      { raw: raw, rendered: rendered }
    end

    def guid_field
      json = { rendered: guid_url }
      json[:raw] = guid_url if edit?
      json
    end

    def guid_url
      # get_the_guid(): the upload's own URL once the file exists.
      source_url.presence || "#{Entity.site.home_url}/?attachment_id=#{asset.id}"
    end

    def image? = asset.mime_type.to_s.start_with?("image/")
    def metadata = asset.metadata.is_a?(Hash) ? asset.metadata : {}
    def relative_file = metadata["file"].to_s
    def upload_dir = File.dirname(relative_file)
    def uploads_baseurl = "#{Entity.site.home_url}#{UPLOADS}"
    def source_url = relative_file.empty? ? "" : "#{uploads_baseurl}/#{relative_file}"

    def size_url(file) = "#{uploads_baseurl}/#{upload_dir}/#{file}"

    def rendered_title
      Entity.text.capital_p_title(Entity.text.convert_chars(Entity.text.wptexturize(asset.title.to_s)).strip)
    end

    # the_excerpt on the caption (wpautop over the texturized caption).
    def rendered_caption
      raw = asset.caption.to_s
      return "" if raw.strip.empty?

      Entity.text.wpautop(Entity.text.convert_chars(Entity.text.wptexturize(raw)))
    end

    # prepend_attachment(): the image is prepended, then the_content over post_content.
    # The Asset aggregate holds no post_content, so only the prepend markup is produced.
    def rendered_description
      return "" unless image?

      full = source_url
      %(<p class="attachment"><a href='#{full}'>) +
        image_tag +
        "</a></p>\n"
    end

    def medium_or_full_file
      (metadata.dig("sizes", "medium", "file") || File.basename(relative_file)).to_s
    end

    # A minimal `wp_get_attachment_image('medium')` for the prepend markup.
    def image_tag
      sizes = metadata["sizes"] || {}
      med = sizes["medium"] || {}
      w = (med["width"] || metadata["width"]).to_i
      h = (med["height"] || metadata["height"]).to_i
      alt = Entity.text.esc_attr(Entity.text.strip_all_tags(asset.alt_text.to_s))
      %(<img loading="lazy" decoding="async" width="#{w}" height="#{h}" ) +
        %(src="#{size_url(medium_or_full_file)}" class="attachment-medium size-medium" alt="#{alt}" />)
    end

    def media_details
      return {} unless image? && metadata["width"]

      {
        width: metadata["width"].to_i,
        height: metadata["height"].to_i,
        file: relative_file,
        # wp_prepare_attachment_for_js()/the REST controller both surface the byte size
        # of the "full" file inside media_details (verified on the oracle).
        filesize: (metadata["filesize"] || asset.byte_size).to_i,
        sizes: size_table,
        image_meta: metadata["image_meta"] || {}
      }
    end

    # Each generated size, plus the `full` size the REST controller appends.
    def size_table
      table = {}
      (metadata["sizes"] || {}).each do |name, s|
        entry = {
          file: s["file"].to_s,
          width: s["width"].to_i,
          height: s["height"].to_i
        }
        entry[:filesize] = s["filesize"].to_i if s["filesize"]
        entry[:mime_type] = (s["mime-type"] || s["mime_type"]).to_s
        entry[:source_url] = size_url(s["file"].to_s)
        table[name] = entry
      end
      table["full"] = {
        file: File.basename(relative_file),
        width: metadata["width"].to_i,
        height: metadata["height"].to_i,
        mime_type: asset.mime_type.to_s,
        source_url: source_url
      }
      table
    end

    def missing_image_sizes
      return [] unless image?

      generated = (metadata["sizes"] || {}).keys
      Library::Asset.registered_sizes.keys - generated
    end

    # `exif_orientation` (7.2): the stored EXIF orientation, 1 when the image carries
    # none. Library::Asset rewrites it to "1" once it has rotated the bytes.
    def exif_orientation
      value = metadata.dig("image_meta", "orientation").to_i
      value.positive? ? value : 1
    end

    # get_attachment_link(): nested under the parent post's permalink.
    def attachment_link
      parent = asset.attached_to_id && Publishing::Post.find_by(id: asset.attached_to_id)
      return "#{Entity.site.home_url}/?attachment_id=#{asset.id}" unless parent

      "#{Entity.links.permalink(parent)}#{asset.slug}/"
    end

    def links_for
      out = {
        self: [{ href: Url.rest("/wp/v2/media/#{asset.id}"), targetHints: { allow: @allow } }],
        collection: [{ href: Url.rest("/wp/v2/media") }],
        about: [{ href: Url.rest("/wp/v2/types/attachment") }],
        author: [{ embeddable: true, href: Url.rest("/wp/v2/users/#{asset.uploader_id}") }],
        replies: [{ embeddable: true, href: Url.rest("/wp/v2/comments?post=#{asset.id}") }]
      }
      # class-wp-rest-attachments-controller.php:1063 — only for an ATTACHED asset.
      if (parent = attached_parent)
        out[:"wp:attached-to"] = [{
          embeddable: true,
          post_type: parent.is_a?(Publishing::Page) ? "page" : "post",
          id: parent.id,
          href: Url.rest("/wp/v2/#{parent.is_a?(Publishing::Page) ? "pages" : "posts"}/#{parent.id}")
        }]
      end
      # rest_prepare_* action links (class-wp-rest-posts-controller.php:1660): only in
      # `edit`, and only for the rights the controller said the actor holds.
      @actions.each do |action|
        out[:"wp:action-#{action}"] = [{ href: Url.rest("/wp/v2/media/#{asset.id}") }]
      end
      # class-wp-rest-server.php:1332 — the curies block appears exactly when at least
      # one `wp:` rel does.
      out[:curies] = Entity.curies if out.keys.any? { |rel| rel.to_s.start_with?("wp:") }
      out
    end

    def attached_parent
      return nil if asset.attached_to_id.blank?

      @attached_parent ||= Publishing::Post.find_by(id: asset.attached_to_id)
    end
  end
end
