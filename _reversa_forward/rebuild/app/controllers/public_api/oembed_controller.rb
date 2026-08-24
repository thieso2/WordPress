# frozen_string_literal: true

module PublicApi
  # /wp-json/oembed/1.0/embed — WP_oEmbed_Controller::get_item()
  # (wp-includes/class-wp-oembed-controller.php:206), the target of every golden page's
  # `<link rel="alternate" type="application/json+oembed" href=".../oembed/1.0/embed?url=…">`
  # discovery tag, so it MUST resolve.
  #
  # No permission callback -> public (BR-REST-05). `get_oembed_response_data()`
  # (wp-includes/embed.php:1013): the `url` is resolved to a post; an unresolvable or
  # non-public URL is `oembed_invalid_url` (404).
  #
  # ⚠️ `html` carries a per-request `data-secret` (wp_generate_password(10), embed.php:497)
  # — it is non-deterministic in the LEGACY too (a fresh secret each call), so the field
  # cannot be byte-stable; the structure and every other field are faithful.
  class OembedController < BaseController
    EMBED_SCRIPT = Rails.root.join("public/wp-includes/js/wp-embed.min.js")

    def embed
      post = resolve_post(params[:url].to_s)
      unless post
        raise PublicApi::RestError.new("oembed_invalid_url", "Not Found", 404)
      end

      render_json(oembed_data(post))
    end

    private

    # A minimal url_to_postid(): match the last path segment (the post/page slug) to a
    # published post whose permalink equals the requested URL.
    def resolve_post(url)
      home = Entity.site.home_url
      return nil unless url.start_with?(home)

      path = url.sub(home, "").split("?", 2).first.to_s
      slug = path.split("/").reject(&:empty?).last
      return nil if slug.blank?

      candidates = Publishing::Post.where(status: "published", slug: slug).to_a
      candidates.detect { |p| same_url?(Entity.links.permalink(p), url) } || candidates.first
    end

    def same_url?(a, b) = a.to_s.chomp("/") == b.to_s.split("?", 2).first.to_s.chomp("/")

    # get_oembed_response_data(): width capped at 600, height at the 16:9 ratio (min 200).
    def oembed_data(post)
      maxwidth = params[:maxwidth].present? ? params[:maxwidth].to_i : 600
      width = [maxwidth, 600].min
      width = 600 if width <= 0
      height = [(width / 16.0 * 9).ceil, 200].max

      author = post.author
      {
        version: "1.0",
        provider_name: Configuration::Setting["blogname"].to_s,
        provider_url: Entity.site.home_url,
        author_name: author&.display_name.to_s,
        author_url: author ? Entity.links.author_posts_url(author) : "",
        title: Entity.text.the_title(post),
        type: "rich",
        width: width,
        height: height,
        html: embed_html(post, width, height)
      }
    end

    # get_post_embed_html(), embed.php:497 — the blockquote + sandboxed iframe + the
    # inline wp-embed.min.js loader.
    def embed_html(post, width, height)
      secret = SecureRandom.alphanumeric(10)
      permalink = Entity.links.permalink(post)
      title = Entity.text.the_title(post)
      iframe_title = %(&#8220;#{title}&#8221; &#8212; #{Configuration::Setting["blogname"]})

      blockquote = %(<blockquote class="wp-embedded-content" data-secret="#{secret}">) +
                   %(<a href="#{permalink}">#{title}</a></blockquote>)
      iframe = %(<iframe sandbox="allow-scripts" security="restricted" ) +
               %(src="#{permalink}embed/#?secret=#{secret}" width="#{width}" height="#{height}" ) +
               %(title="#{iframe_title}" data-secret="#{secret}" frameborder="0" marginwidth="0" ) +
               %(marginheight="0" scrolling="no" class="wp-embedded-content"></iframe>)
      "#{blockquote}#{iframe}#{embed_script}"
    end

    def embed_script
      body = File.read(EMBED_SCRIPT).chomp
      "<script>\n#{body}\n//# sourceURL=#{Entity.site.home_url}/wp-includes/js/wp-embed.min.js\n</script>\n"
    end
  end
end
