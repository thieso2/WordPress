# frozen_string_literal: true

module Web
  # `wp-comments-post.php` — the first public WRITE endpoint (Wave 3).
  #
  # The route is the literal legacy path: the comment form's `action` is
  # `site_url('/wp-comments-post.php')` (comment-template.php:2516, rendered by
  # Composition::Renderers::CommentBlocks::PostCommentsForm) and every golden records
  # it. Field names are the legacy's (Discussion::Submission::FIELDS plus
  # `wp-comment-cookies-consent` and `redirect_to`).
  #
  # The script is 80 lines and does four things; each is one method below:
  #   :8-18   anything but POST → 405, `Allow: POST`, text/plain, no body
  #   :23     nocache_headers()
  #   :25-40  wp_handle_comment_submission() → Discussion::Submission; a WP_Error with
  #           data is a wp_die() page with that status, one without is an empty 200
  #   :42-55  the commenter cookies (set_comment_cookies → wp_set_comment_cookies)
  #   :57-80  the redirect (get_comment_link / redirect_to, the moderation arguments,
  #           wp_safe_redirect)
  #
  # ⚠️ No CSRF token. The legacy form carries none for an anonymous commenter — the only
  # token on this path is `_wp_unfiltered_html_comment`, and it governs the kses level,
  # not admission — so Rails' request-forgery check is skipped for this action alone.
  class CommentsController < ApplicationController
    skip_forgery_protection only: :create

    # wp_die()'s title for this script, wp-comments-post.php:31 (LITERAL).
    FAILURE_TITLE = "Comment Submission Failure"

    # nocache_headers(), functions.php — wp_get_nocache_headers() unfiltered.
    NOCACHE_EXPIRES = "Wed, 11 Jan 1984 05:00:00 GMT"
    NOCACHE_CONTROL = "no-cache, must-revalidate, max-age=0, no-store, private"

    # wp-comments-post.php:8-18.
    def method_not_allowed
      response.headers["Allow"] = "POST"
      render plain: "", status: :method_not_allowed
    end

    # wp-comments-post.php:21-81.
    def create
      nocache_headers!

      comment = Discussion::Submission.new(
        fields: submission_fields, actor: current_actor,
        remote_ip: request.remote_ip, user_agent: request.user_agent,
        html_filter: html_filter, can_read_post: method(:can_read_post?)
      ).call

      # :43 — `isset( $_POST['wp-comment-cookies-consent'] )`: presence, not value.
      consent = params.key?("wp-comment-cookies-consent")
      Discussion::CommenterCookies.header_lines(comment, user: current_actor, consent: consent)
                                  .each { |line| add_set_cookie(line) }

      location = Discussion::PostSubmitLocation.call(
        comment, comment_link: Composition::Renderers::CommentBlocks::Urls.comment_link(comment, comment.post),
        redirect_to: params["redirect_to"].is_a?(String) ? params["redirect_to"] : nil,
        consent: consent, request_path: request.fullpath
      )
      # wp_redirect(), pluggable.php:1510-1516: `X-Redirect-By: WordPress`, then the
      # Location EXACTLY as validated — a relative `redirect_to` stays relative. Rails'
      # redirect_to would absolutise it against the request host, so the header is set
      # by hand.
      response.headers["X-Redirect-By"] = "WordPress"
      response.headers["Location"] = location
      render html: "", status: :found
    rescue Discussion::Comment::Rejected => e
      submission_failure(e)
    end

    private

    # wp-comments-post.php:26-40. `(int) $comment->get_error_data()` — a status means a
    # wp_die() page; none means `exit` with nothing.
    def submission_failure(error)
      if error.http_status
        render html: failure_page(error.message).html_safe, status: error.http_status # rubocop:disable Rails/OutputSafety
      else
        render html: "", status: :ok
      end
    end

    # _default_wp_die_handler(), functions.php:3907, with the arguments
    # wp-comments-post.php:29-36 passes: the message wrapped in <p>, the LITERAL title,
    # `back_link => true`. The document is the oracle's own capture of that handler
    # (one file, one placeholder) rather than a re-typed template, and it is served as
    # bytes rather than through an ERB view so that no environment setting — the
    # development annotation of rendered views, a layout — can touch it.
    def failure_page(message)
      FAILURE_DOCUMENT.sub("{{MESSAGE}}") { "<p>#{message}</p>" }
    end

    FAILURE_DOCUMENT = Rails.root.join("app/views/web/comments/failure.html").read.freeze
    private_constant :FAILURE_DOCUMENT

    # The legacy fields, exactly as posted: strings stay strings, anything else (an
    # array-shaped parameter) is handed over as-is for Submission to treat as unset.
    def submission_fields
      Discussion::Submission::FIELDS.each_with_object({}) do |name, out|
        next unless params.key?(name)

        value = params[name]
        out[name] = value.is_a?(String) ? value : value.to_unsafe_h
      rescue NoMethodError
        out[name] = value.to_a
      end
    end

    # comment.php:4083-4093. An `unfiltered_html` holder escapes kses only with a valid
    # `_wp_unfiltered_html_comment` nonce for this post; everyone else is :restricted.
    # Access::RoleCatalogue is consulted HERE, on the surface, so Discussion never
    # references Access.
    def html_filter
      return :restricted if current_actor.nil?
      return :restricted unless Access::RoleCatalogue.capabilities_for(current_actor.roles).include?("unfiltered_html")

      nonce = params["_wp_unfiltered_html_comment"]
      action = "unfiltered-html-comment_#{params["comment_post_ID"].to_i}"
      Identity::Nonce.verify(nonce, action, session_token: current_session_token) ? :none : :restricted
    end

    # current_user_can( 'read_post', $id ) through the policy the record's type carries.
    def can_read_post?(post)
      policy = post.is_a?(Publishing::Page) ? Access::PagePolicy : Access::PostPolicy
      policy.new(current_actor, post).permit?(:read)
    end

    # The raw session token the nonce was minted under. There is no session surface
    # until Wave 4; until then a logged-in actor cannot exist here either.
    def current_session_token = nil

    def nocache_headers!
      response.headers["Expires"] = NOCACHE_EXPIRES
      response.headers["Cache-Control"] = NOCACHE_CONTROL
    end

    # Rack 3 carries Set-Cookie as an array of lines; appending keeps whatever the cookie
    # jar may add of its own.
    def add_set_cookie(line)
      existing = response.headers["Set-Cookie"]
      response.headers["Set-Cookie"] = Array(existing).flat_map { |v| v.to_s.split("\n") } + [line]
    end
  end
end
