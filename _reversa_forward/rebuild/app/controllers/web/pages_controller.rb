# frozen_string_literal: true

module Web
  # web.page / web.privacy_policy. Hierarchical: BR-MIGRATE-033 scopes a page's slug to
  # (type, parent), so `child-page` may legally appear under two different parents and
  # the full path is what disambiguates.
  #
  # ⚠️ `web.privacy_policy` is not a different SCREEN here, and that is the legacy's own
  # answer: `is_privacy_policy()` is true, `get_privacy_policy_template()` finds no
  # `privacy-policy.html` in twentytwentyfive, and the loop falls through to `is_page()`.
  # Confirmed against the oracle — /privacy-policy/ renders `twentytwentyfive//page`.
  # The only difference it makes is the `privacy-policy` body class.
  class PagesController < ApplicationController
    def show
      segments = params[:path].to_s.split("/").reject(&:empty?)
      return not_found if segments.empty?

      post = walk(segments)
      return not_found if post.nil?

      render_screen(Presentation::Screen.new(kind: :page, post: post))
    end

    private

    # Resolve the path one segment at a time against (parent_id, slug) -- the same scope
    # the unique index enforces.
    def walk(segments)
      parent_id = nil
      node = nil
      segments.each do |segment|
        node = Publishing::Page.where(status: %w[published private], parent_id: parent_id)
                               .find_by(slug: segment)
        return nil if node.nil?

        parent_id = node.id
      end
      node
    end

    def not_found
      render_screen(Presentation::Screen.new(kind: :not_found), status: :not_found)
    end
  end
end
