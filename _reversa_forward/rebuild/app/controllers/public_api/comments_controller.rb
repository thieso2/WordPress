# frozen_string_literal: true

module PublicApi
  # /wp/v2/comments — WP_REST_Comments_Controller. The collection has no permission
  # callback, so it is PUBLIC (BR-REST-05); WHICH comments appear is constrained inside
  # the action to `approved` comments on readable (published) posts — an anonymous caller
  # can never widen past that (get_items forces status=approve for a caller without
  # `moderate_comments`, :340). Default order is date_gmt DESC (:390).
  #
  # Item: a `read_item` permission callback is registered — a missing id is
  # rest_comment_invalid_id (404); an unapproved comment or one on an unreadable post is
  # denied 401/403 (BR-REST-04/06).
  #
  # ── The WRITE surface ────────────────────────────────────────────────────────────
  # ⚠️ ANONYMOUS COMMENTING IS PERMANENTLY CLOSED ON THIS SURFACE, and that is the
  # legacy's own answer, not a hardening. create_item_permissions_check() (:640) lets an
  # anonymous submitter through only when the `rest_allow_anonymous_comments` filter
  # returns true, and it defaults to FALSE. AD-01 removes the filter, so the default is
  # the whole rule — permanently. Verified on the oracle: an anonymous POST answers
  # rest_comment_login_required 401 whatever the payload. The FORM path
  # (wp-comments-post.php → Discussion::Submission → Web::CommentsController) is the
  # surface that still admits anonymous authors, and it is untouched by this.
  #
  # The moderation pipeline is NOT reimplemented here: Discussion::Comment.moderate is
  # the one place a verdict is decided (flood, duplicate, disallowed keys, held), and its
  # two non-verdict refusals (Comment::Rejected) are re-statused the way the REST
  # controller re-statuses them — comment_duplicate 409, comment_flood 400 (:490-500).
  class CommentsController < BaseController
    include CollectionPagination
    include WriteSupport

    permission :show,    :read_item
    permission :create,  :create_item
    permission :update,  :update_item
    permission :destroy, :delete_item

    # The REST `status` vocabulary → the AGG-Comment enum (:1900, read backwards).
    STATUS_INPUT = { "approved" => "approved", "approve" => "approved", "1" => "approved",
                     "hold" => "pending", "0" => "pending", "unapproved" => "pending",
                     "spam" => "spam", "trash" => "trashed" }.freeze

    # wp_new_comment(): `substr( $commentdata['comment_agent'], 0, 254 )`.
    AGENT_MAX_BYTES = 254

    def index
      scope = readable_scope
      scope = scope.where(post_id: params[:post].to_i) if params[:post].present?
      total = scope.count
      records = scope.order(submitted_at: :desc, id: :desc)
                     .offset((page_param - 1) * per_page_param).limit(per_page_param).to_a
      set_pagination_headers(total: total, base_path: "/wp/v2/comments")
      set_allow_header(collection_allow)
      render_json(records.map { |c| CommentSerializer.new(c, context: context, allow: item_allow(c)).as_json })
    end

    def show
      comment = loaded_comment
      set_allow_header(item_allow(comment))
      render_json(CommentSerializer.new(comment, context: context, allow: item_allow(comment)).as_json)
    end

    # POST /wp/v2/comments — create_item(), :450.
    def create
      post = requested_post
      content = raw_text(params[:content])
      if content.strip.empty?
        raise PublicApi::RestError.new("rest_comment_content_invalid", "Invalid comment content.", 400)
      end

      comment = moderate!(post, content)
      # :505 — an explicit `status` is applied AFTER the moderation verdict, and only a
      # moderator may send one (the permission callback already refused anyone else).
      apply_status!(comment) if sent?(:status)

      set_allow_header(item_allow(comment))
      # :520 — the created comment is answered in `edit` context.
      render_created(CommentSerializer.new(comment, context: "edit", allow: item_allow(comment)).as_json,
                     location: Url.rest("/wp/v2/comments/#{comment.id}"))
    end

    # POST|PUT|PATCH /wp/v2/comments/:id — update_item(), :560.
    def update
      comment = loaded_comment
      attributes = {}
      attributes[:content] = Discussion::FieldFilters.content(raw_text(params[:content]), html_filter: html_filter) if sent?(:content)
      attributes[:author_name] = Discussion::FieldFilters.author_name(params[:author_name].to_s) if sent?(:author_name)
      attributes[:author_email] = Discussion::FieldFilters.author_email(params[:author_email].to_s).presence if sent?(:author_email)
      attributes[:author_url] = Discussion::FieldFilters.author_url(params[:author_url].to_s).presence if sent?(:author_url)
      attributes[:user_id] = params[:author].to_i.positive? ? params[:author].to_i : nil if sent?(:author)
      attributes[:submitted_at] = parse_date(params[:date_gmt] || params[:date]) if sent?(:date_gmt) || sent?(:date)
      attributes[:parent_id] = params[:parent].to_i.positive? ? params[:parent].to_i : nil if sent?(:parent)
      attributes[:post_id] = params[:post].to_i if sent?(:post) && params[:post].to_i.positive?
      comment.update!(attributes) if attributes.any?
      apply_status!(comment) if sent?(:status)

      set_allow_header(item_allow(comment))
      render_json(CommentSerializer.new(comment.reload, context: "edit", allow: item_allow(comment)).as_json)
    end

    # DELETE /wp/v2/comments/:id — delete_item(), :640. A comment DOES support trashing:
    # without `force` it moves to `trash`, and trashing an already-trashed comment is
    # rest_already_trashed (410).
    def destroy
      comment = loaded_comment
      if force_param?
        previous = CommentSerializer.new(comment, context: "edit", allow: item_allow(comment)).as_json.except(:_links)
        comment.destroy!
        set_allow_header(%w[GET POST PUT PATCH DELETE])
        return render_json({ deleted: true, previous: previous })
      end

      if comment.status.to_s == "trashed"
        raise PublicApi::RestError.new("rest_already_trashed", "The comment has already been trashed.", 410)
      end

      comment.trash!(by: current_actor)
      set_allow_header(item_allow(comment))
      render_json(CommentSerializer.new(comment.reload, context: "edit", allow: item_allow(comment)).as_json)
    end

    private

    # Approved comments whose post is published (the anonymous-visible set).
    def readable_scope
      published_ids = Publishing::Post.where(status: "published").select(:id)
      Discussion::Comment.where(status: "approved", post_id: published_ids)
                         .includes(:post, :user)
    end

    # ── writing ─────────────────────────────────────────────────────────────────

    # wp_allow_comment() + wp_insert_comment(), through the ONE pipeline that owns the
    # verdict (AGG-Comment). Its two non-verdict refusals are re-statused as the REST
    # controller re-statuses them (:490): duplicate 409, flood 400, everything else the
    # rejection's own status.
    def moderate!(post, content)
      Discussion::Comment.moderate(comment_attributes(post, content), actor: current_actor)
    rescue Discussion::Comment::Rejected => e
      status = case e.code
               when "comment_duplicate" then 409
               when "comment_flood" then 400
               else e.http_status || 400
               end
      raise PublicApi::RestError.new(e.code, e.message, status)
    rescue ActiveRecord::RecordInvalid => e
      raise PublicApi::RestError.new("rest_comment_invalid", e.record.errors.full_messages.join(" "), 400)
    end

    # prepare_item_for_database(), :1180. A field the caller omitted falls back to the
    # AUTHENTICATED USER's own — :470-486, which is why an admin's comment comes back
    # carrying their display name, email and site URL.
    def comment_attributes(post, content)
      author = author_user
      {
        post: post,
        parent_id: params[:parent].to_i.positive? ? params[:parent].to_i : nil,
        user_id: author&.id,
        author_name: Discussion::FieldFilters.author_name(
          sent?(:author_name) ? params[:author_name].to_s : (author&.display_name.presence || author&.login.to_s)
        ),
        author_email: Discussion::FieldFilters.author_email(
          sent?(:author_email) ? params[:author_email].to_s : author&.email.to_s
        ).presence,
        author_url: Discussion::FieldFilters.author_url(
          sent?(:author_url) ? params[:author_url].to_s : author&.url.to_s
        ).presence,
        author_ip: (sent?(:author_ip) ? params[:author_ip].to_s : request.remote_ip).presence,
        user_agent: request.user_agent.to_s.byteslice(0, AGENT_MAX_BYTES).to_s.scrub("").presence,
        content: Discussion::FieldFilters.content(content, html_filter: html_filter),
        kind: "comment",
        submitted_at: (sent?(:date_gmt) || sent?(:date)) ? parse_date(params[:date_gmt] || params[:date]) : Time.current
      }
    end

    # `author` names the USER the comment belongs to; the permission callback already
    # refused anyone naming someone else without `moderate_comments`.
    def author_user
      return Identity::User.find_by(id: params[:author].to_i) if params[:author].to_i.positive?

      current_actor
    end

    # handle_status_param(), :1740 — approve / hold / spam / trash, each recording a
    # ModerationVerdict row so the decision stays auditable (AGG-Comment).
    def apply_status!(comment)
      case STATUS_INPUT[params[:status].to_s.downcase]
      when "approved" then comment.approve!(by: current_actor)
      when "pending"  then comment.unapprove!(by: current_actor)
      when "spam"     then comment.mark_spam!(by: current_actor)
      when "trashed"  then comment.trash!(by: current_actor)
      end
    end

    # wp_filter_comment(): a submitter holding `unfiltered_html` keeps their markup.
    def html_filter
      return :restricted if current_actor.nil?

      Access::RoleCatalogue.capabilities_for(current_actor.roles).include?("unfiltered_html") ? :none : :restricted
    end

    # rest_parse_date(): an unparseable value is ignored rather than fatal.
    def parse_date(value)
      Time.zone.parse(value.to_s) || Time.current
    rescue ArgumentError
      Time.current
    end

    # ── permission callbacks (class-wp-rest-comments-controller.php) ────────────

    def read_item
      comment = loaded_comment
      return true if comment.status.to_s == "approved" &&
                     comment.post&.status.to_s == "published"

      # A held/spam comment, or one on a non-public post, needs moderate/edit rights.
      current_actor && Access::SitePolicy.new(current_actor, nil).permit?(:moderate_comments)
    end

    # create_item_permissions_check(), :640, in the legacy's own order.
    def create_item
      # :645 — `rest_allow_anonymous_comments` is permanently false under AD-01.
      unless current_actor
        raise PublicApi::RestError.new("rest_comment_login_required",
                                       "Sorry, you must be logged in to comment.", 401)
      end

      # :668-700 — author, author_ip and status may only be set by a moderator.
      if sent?(:author) && params[:author].to_i != current_actor.id && !moderator?
        raise rest_denied("rest_comment_invalid_author",
                          "Sorry, you are not allowed to edit 'author' for comments.")
      end
      if sent?(:author_ip) && !moderator? && params[:author_ip].to_s != request.remote_ip
        raise rest_denied("rest_comment_invalid_author_ip",
                          "Sorry, you are not allowed to edit 'author_ip' for comments.")
      end
      if sent?(:status) && !moderator?
        raise rest_denied("rest_comment_invalid_status",
                          "Sorry, you are not allowed to edit 'status' for comments.")
      end

      post = requested_post # raises rest_comment_invalid_post_id (403) when absent/unknown

      # :718 / :726 — a draft or trashed post takes no comments.
      if post.trashed?
        raise PublicApi::RestError.new("rest_comment_trash_post",
                                       "Sorry, you are not allowed to create a comment on this post.", 403)
      end
      unless post.published? || post.private?
        raise PublicApi::RestError.new("rest_comment_draft_post",
                                       "Sorry, you are not allowed to create a comment on this post.", 403)
      end
      unless Access::PostPolicy.for(current_actor, post).permit?(:read)
        raise rest_denied("rest_cannot_read_post", "Sorry, you are not allowed to read the post for this comment.")
      end
      # :742 — comments_open().
      unless post.comment_status.to_s == "open"
        raise PublicApi::RestError.new("rest_comment_closed", "Sorry, comments are closed for this item.", 403)
      end
      true
    end

    def update_item
      comment = loaded_comment
      return true if Access::CommentPolicy.new(current_actor, comment).permit?(:edit)

      raise rest_denied("rest_cannot_edit", "Sorry, you are not allowed to edit this comment.")
    end

    def delete_item
      comment = loaded_comment
      return true if Access::CommentPolicy.new(current_actor, comment).permit?(:delete)

      raise rest_denied("rest_cannot_delete", "Sorry, you are not allowed to delete this comment.")
    end

    def moderator?
      current_actor && Access::SitePolicy.new(current_actor, nil).permit?(:moderate_comments)
    end

    # :710 — an absent `post` and a `post` that names nothing are the SAME refusal, and
    # it is 403 rather than 404 (the legacy's own choice; verified on the oracle).
    def requested_post
      @requested_post ||= (params[:post].to_i.positive? && Publishing::Post.find_by(id: params[:post].to_i)) ||
                          raise(PublicApi::RestError.new(
                            "rest_comment_invalid_post_id",
                            "Sorry, you are not allowed to create this comment without a post.", 403
                          ))
    end

    # ── rest_send_allow_header() / targetHints ──────────────────────────────────

    def item_allow(comment)
      allow = %w[GET]
      return allow if current_actor.nil?

      policy = Access::CommentPolicy.new(current_actor, comment)
      allow.concat(%w[POST PUT PATCH]) if policy.permit?(:edit)
      allow << "DELETE" if policy.permit?(:delete)
      allow
    end

    def collection_allow
      allow = %w[GET]
      allow << "POST" if current_actor
      allow
    end

    def loaded_comment
      @loaded_comment ||= Discussion::Comment.find_by(id: params[:id]) ||
                          raise(PublicApi::RestError.new("rest_comment_invalid_id",
                                                         "Invalid comment ID.", 404))
    end
  end
end
