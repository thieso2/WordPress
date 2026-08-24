# frozen_string_literal: true

module PublicApi
  # WP_REST_Attachments_Controller::prepare_item_for_response(), `view` context
  # (wp-includes/rest-api/endpoints/class-wp-rest-attachments-controller.php:660). It
  # extends the posts response with the attachment-specific fields (alt_text,
  # media_type, mime_type, media_details, source_url, filename, filesize).
  #
  # ⚠️ VALUE-PARITY LIMITATION (reported, not faked). The Library::Asset aggregate
  # (owned by the media track) is a SEPARATE table from posts, so:
  #   * `id` is the asset's own id (1..), not the shared wp_posts id (26..) the oracle
  #     emits — attachments do not live in the post id-space here (AGG-Asset ruling).
  #   * `date`/`modified` are the row's created/updated timestamps (the seed did not
  #     preserve the legacy post_date), and `filesize` is 0 (bytes are not re-stored).
  #   * there is NO post_content column, so `description.rendered` carries only the
  #     `prepend_attachment` image markup, never the description prose the oracle shows.
  # The SHAPE and the derivable fields (media_details from `metadata`, source_url, the
  # size table, image_meta) are faithful; the identity fields above cannot be without a
  # cross-track schema change. See the handoff report.
  class MediaSerializer
    include Entity

    UPLOADS = "/wp-content/uploads"

    def initialize(asset)
      @asset = asset
    end

    def self.collection(assets) = assets.map { |a| new(a).as_json }

    def as_json
      {
        id: asset.id,
        date: iso(asset.created_at),
        date_gmt: iso(asset.created_at),
        guid: { rendered: "#{Entity.site.home_url}/?attachment_id=#{asset.id}" },
        modified: iso(asset.updated_at || asset.created_at),
        modified_gmt: iso(asset.updated_at || asset.created_at),
        slug: asset.slug.to_s,
        status: "inherit",
        type: "attachment",
        link: attachment_link,
        title: { rendered: rendered_title },
        author: asset.uploader_id.to_i,
        featured_media: 0,
        comment_status: "open",
        ping_status: "closed",
        template: "",
        meta: [],
        class_list: %W[post-#{asset.id} attachment type-attachment status-inherit hentry],
        description: { rendered: rendered_description },
        caption: { rendered: rendered_caption },
        alt_text: asset.alt_text.to_s,
        media_type: image? ? "image" : "file",
        mime_type: asset.mime_type.to_s,
        media_details: media_details,
        post: asset.attached_to_id.to_i,
        source_url: source_url,
        filename: File.basename(relative_file),
        filesize: asset.byte_size.to_i,
        _links: links_for
      }
    end

    private

    attr_reader :asset

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
        sizes: size_table,
        image_meta: metadata["image_meta"] || {}
      }
    end

    # Each generated size, plus the `full` size the REST controller appends.
    def size_table
      table = {}
      (metadata["sizes"] || {}).each do |name, s|
        table[name] = {
          file: s["file"].to_s,
          width: s["width"].to_i,
          height: s["height"].to_i,
          mime_type: (s["mime-type"] || s["mime_type"]).to_s,
          source_url: size_url(s["file"].to_s)
        }
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

    # get_attachment_link(): nested under the parent post's permalink.
    def attachment_link
      parent = asset.attached_to_id && Publishing::Post.find_by(id: asset.attached_to_id)
      return "#{Entity.site.home_url}/?attachment_id=#{asset.id}" unless parent

      "#{Entity.links.permalink(parent)}#{asset.slug}/"
    end

    def links_for
      {
        self: [{ href: Url.rest("/wp/v2/media/#{asset.id}"), targetHints: { allow: %w[GET] } }],
        collection: [{ href: Url.rest("/wp/v2/media") }],
        about: [{ href: Url.rest("/wp/v2/types/attachment") }],
        author: [{ embeddable: true, href: Url.rest("/wp/v2/users/#{asset.uploader_id}") }],
        replies: [{ embeddable: true, href: Url.rest("/wp/v2/comments?post=#{asset.id}") }]
      }
    end
  end
end
