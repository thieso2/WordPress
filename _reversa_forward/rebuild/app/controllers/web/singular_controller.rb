# frozen_string_literal: true

module Web
  # web.singular / web.single / web.comments -- all three are the same URL and the same
  # `single` block template; the manifest names them separately because they assert
  # different things about it.
  class SingularController < ApplicationController
    def show
      # ⚠️ `private` is NOT publicly readable. WP gates it on the `read_private_posts`
      # capability (map_meta_cap() -> 'read_post', wp-includes/class-wp-query.php's
      # `get_posts()` only widens the status set for a user who has it); an anonymous
      # visitor gets the 404 template. The front end has no actor at all
      # (ApplicationController#current_actor is nil on every Web:: surface), so the
      # visible set here is `published` and nothing else.
      # ⚠️ Before this, /2026/03/private-article/ rendered the private article's full
      # title and body to anonymous visitors while the oracle answered 404. Found by the
      # corpus-widening pass; the 25-request corpus contained no private URL.
      post = Publishing::Article.where(status: %w[published])
                                .find_by(slug: encoded_slug)
      # A slug that moved leaves a Routing::Redirect behind, replacing the legacy's
      # `_wp_old_slug` postmeta (AD-03).
      if post.nil? && (redirect = Routing::Redirect.find_by(from_path: "/#{params[:slug]}"))
        return redirect_to(permalink_for(redirect.post), status: :moved_permanently) if redirect.post
      end
      return not_found if post.nil?

      render_screen(Presentation::Screen.new(kind: :single, post: post))
    end

    private

    # BR-MIGRATE-033, the same rule AttachmentsController applies: post_name is stored the
    # way sanitize_title_with_dashes() wrote it — non-ASCII characters percent-encoded in
    # LOWERCASE hex (`utf8_uri_encode()`, wp-includes/formatting.php:1160, then
    # strtolower at :2296) — and class-wp.php:239 matches the RAW request segment against
    # it. Rails hands the segment over decoded, so it is re-encoded before the lookup;
    # without this `/2026/03/emoji-%f0%9f%98%80…/` and the quoted-title article 404 here
    # while the oracle serves them.
    def encoded_slug
      params[:slug].to_s.gsub(/[^\x00-\x7F]/) do |char|
        char.bytes.map { |byte| format("%%%02x", byte) }.join
      end
    end

    def permalink_for(post)
      "/#{post.published_at.strftime("%Y/%m")}/#{post.slug}"
    end

    def not_found
      render_screen(Presentation::Screen.new(kind: :not_found), status: :not_found)
    end
  end
end
