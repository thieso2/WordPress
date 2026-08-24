# frozen_string_literal: true

module Console
  # console.comment — the single-comment edit screen (P-EDIT). Legacy origin:
  # wp-admin/comment.php `case 'editcomment'` (:104) rendering edit-form-comment.php, and
  # `case 'editedcomment'` (:357) calling edit_comment() (wp-admin/includes/comment.php:54).
  #
  # Authorization: current_user_can( 'edit_comment', $id ) — Access::CommentPolicy(:edit),
  # which maps to edit_post on the comment's post (capabilities.php:578).
  class CommentsController < BaseController
    before_action :load_comment
    before_action :authorize_edit

    # GET /console/comments/:id/edit — edit-form-comment.php.
    def edit
      @page_title = "Edit Comment" # <h1>, edit-form-comment.php:22 (LITERAL)
      render :edit
    end

    # PATCH/PUT /console/comments/:id — edit_comment(), includes/comment.php:54-247.
    def update
      # edit_comment() copies newcomment_author* onto comment_author*, comment_status onto
      # comment_approved and content onto comment_content before wp_update_comment().
      @comment.author_name  = params[:newcomment_author].to_s if params.key?(:newcomment_author)
      @comment.author_email = params[:newcomment_author_email].to_s if params.key?(:newcomment_author_email)
      @comment.author_url   = params[:newcomment_author_url].to_s if params.key?(:newcomment_author_url)
      @comment.content      = params[:content].to_s if params.key?(:content)
      if params.key?(:comment_status)
        @comment.status = LEGACY_STATUS.fetch(params[:comment_status].to_s, @comment.status)
      end
      apply_parent if params.key?(:comment_parent)

      if @invalid_parent
        @page_title = "Edit Comment"
        flash.now[:error] = @invalid_parent
        return render :edit, status: :unprocessable_content
      end

      if @comment.save
        # comment.php:377 — redirect back to the referring list with an updated notice.
        flash[:success] = "Comment updated."
        redirect_to edit_console_comment_path(@comment), status: :see_other
      else
        @page_title = "Edit Comment"
        flash.now[:error] = @comment.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_content
      end
    end

    private

    # edit-form-comment.php radio values 1 / 0 / spam (comment_approved), mapped onto the
    # target enum (Discussion::Comment::STATUSES). 'trashed' has no radio — the edit form
    # never sets it (trashing is a list bulk action, edit-comments.php).
    LEGACY_STATUS = { "1" => "approved", "0" => "pending", "spam" => "spam" }.freeze

    def load_comment
      @comment = Discussion::Comment.find_by(id: params[:id])
      not_found!("Invalid comment ID.") if @comment.nil? # comment.php:80
    end

    def authorize_edit
      return if performed?

      # wp-admin/comment.php:85 — wp_die on a comment the actor may not edit.
      authorize!(Access::CommentPolicy, @comment, :edit,
                 "Sorry, you are not allowed to edit this comment.")
    end

    # includes/comment.php:77-105 — the parent may only change with threading enabled, may
    # not be the comment itself, and must belong to the same post. The model's
    # parent_belongs_to_same_post + thread_depth validations back this up; the two
    # threading/self messages are the legacy's own verbatim WP_Errors.
    def apply_parent
      new_parent = params[:comment_parent].to_i
      return if new_parent == @comment.parent_id.to_i

      unless Configuration::Setting["thread_comments"]
        @invalid_parent = "The comment parent cannot be changed because threaded comments are disabled."
        return
      end
      if new_parent == @comment.id
        @invalid_parent = "A comment cannot be a reply to itself."
        return
      end
      @comment.parent_id = new_parent.zero? ? nil : new_parent
    end
  end
end
