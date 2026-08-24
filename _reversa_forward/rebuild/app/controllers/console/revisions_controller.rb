# frozen_string_literal: true

module Console
  # console.revision — the revision comparison screen (P-EDIT, "diff view"). Legacy origin:
  # wp-admin/revision.php, which renders the field-by-field diff between two revisions of a
  # post. Route: /console/posts/:id/revisions.
  #
  # ⚠️ The legacy screen's interaction layer is the React `revisions` bundle (a drag slider
  # over the timeline) — client-side, and unreadable from this checkout (the editor's DEV-012
  # carve-out). What is specified from the extraction is the SERVER side: the revision
  # records (Publishing::Revision, its own table now, AD-02) and the diff of the revisioned
  # fields (Revision::FIELDS, normalize_whitespace). This builds exactly that — a
  # server-rendered diff of `from` → `to` — and leaves the slider as the deferred island.
  #
  # Authorization: revision.php:80 — current_user_can( 'edit_post', $post->ID ) on the
  # PARENT post, through Access::PostPolicy(:edit).
  class RevisionsController < BaseController
    before_action :load_post
    before_action :authorize_edit

    Row = Struct.new(:left, :right, :kind, keyword_init: true) # kind: :same | :del | :add

    # GET /console/posts/:id/revisions.
    def index
      @page_title = "Revisions" # revision.php:113 (LITERAL, used in the <title>)
      # revision.php:107-110 — the heading is 'Compare Revisions of “%s”', where %s is the
      # post title LINKED to the editor, and _draft_or_post_title() substitutes '(no title)'
      # for an empty title. The view builds the linked heading from these two.
      @heading_title = post_title
      @revisions = @post.revisions.regular.newest_first.to_a
      select_pair
      @diffs = Publishing::Revision::FIELDS.index_with { |field| diff_field(field) } if @from || @to
      render :index
    end

    # POST /console/posts/:id/revisions/restore — revision.php action=restore (:36-83).
    # wp_restore_post_revision(): a real state transition on the PARENT post. The route gate
    # is :authenticated; edit_post on the parent is enforced by `authorize_edit` (the
    # before_action above), the same capability revision.php:42 checks. A post held under
    # another editor's live lock is not restored (wp_check_post_lock, :56-58); revisions are
    # gated by wp_revisions_enabled (:51-54). On success it redirects to the editor with the
    # 'restored to revision' message (edit-form-advanced.php:180 / :195, message=5).
    def restore
      revision = @post.revisions.regular.find_by(id: params[:revision])
      return not_found!("Invalid revision ID.") if revision.nil? # revision.php:38-39

      # revision.php:51-54 — don't restore when revisions are disabled (and not an autosave).
      unless Publishing::Post.revisions_enabled?
        return redirect_to edit_console_post_path(@post), status: :see_other
      end

      # revision.php:56-58 — don't restore a post another editor holds locked.
      if @post.edit_lock_holder_if_live(actor: current_actor)
        return redirect_to edit_console_post_path(@post), status: :see_other
      end

      # wp_restore_post_revision() → wp_update_post() of the revisioned fields. The update
      # itself records a fresh revision (Post#record_revision), as the legacy does.
      @post.actor = current_actor
      @post.update!(title: revision.title, content: revision.content, excerpt: revision.excerpt)

      noun = @post.is_a?(Publishing::Page) ? "Page" : "Post"
      when_restored = revision.created_at.strftime("%B %-d, %Y @ %H:%M")
      # edit-form-advanced.php:180 / :195 — 'Post restored to revision from %s.'
      redirect_to edit_console_post_path(@post), status: :see_other,
                  notice: "#{noun} restored to revision from #{when_restored}."
    end

    private

    # revision.php:108 — _draft_or_post_title(): the post title, or '(no title)' when empty.
    def post_title = @post.title.presence || "(no title)"

    def load_post
      @post = Publishing::Post.find_by(id: params[:id])
      not_found!("Invalid post ID.") if @post.nil? # revision.php:47
    end

    def authorize_edit
      return if performed?

      # revision.php:80 — wp_die when the actor may not edit the parent post. PostPolicy.for
      # picks the post/page capability family from the record's type.
      unless Access::PostPolicy.for(current_actor, @post).permit?(:edit)
        deny!("Sorry, you are not allowed to view revisions of this post.")
      end
    end

    # revision.php default: the two most recent revisions (`$compare_two_mode` off compares
    # a revision with its predecessor). `from`/`to` may name specific revision ids.
    def select_pair
      @to   = pick(params[:to])   || @revisions[0]
      @from = pick(params[:from]) || @revisions[@revisions.index(@to).to_i + 1] if @to
    end

    def pick(id) = id.present? ? @revisions.find { |r| r.id == id.to_i } : nil

    # The revisioned-field diff. `from` (older) on the left, `to` (newer) on the right. When
    # there is no older revision, the left side is empty and every line reads as added.
    def diff_field(field)
      old_lines = (@from ? @from.public_send(field) : "").to_s.split("\n", -1)
      new_lines = (@to ? @to.public_send(field) : "").to_s.split("\n", -1)
      line_diff(old_lines, new_lines)
    end

    # A classic LCS line diff — self-contained so the screen carries no runtime gem beyond
    # the app's own (diff-lcs is a test-only dependency). Produces aligned rows the view
    # renders as red (removed) / green (added) / plain (unchanged), the legacy's own
    # left-removed / right-added convention (revision.php help text).
    def line_diff(a, b)
      lcs = lcs_table(a, b)
      rows = []
      i = a.length
      j = b.length
      until i.zero? && j.zero?
        if i.positive? && j.positive? && a[i - 1] == b[j - 1]
          rows.unshift(Row.new(left: a[i - 1], right: b[j - 1], kind: :same))
          i -= 1
          j -= 1
        elsif j.positive? && (i.zero? || lcs[i][j - 1] >= lcs[i - 1][j])
          rows.unshift(Row.new(left: nil, right: b[j - 1], kind: :add))
          j -= 1
        else
          rows.unshift(Row.new(left: a[i - 1], right: nil, kind: :del))
          i -= 1
        end
      end
      rows
    end

    def lcs_table(a, b)
      table = Array.new(a.length + 1) { Array.new(b.length + 1, 0) }
      a.each_index do |x|
        b.each_index do |y|
          table[x + 1][y + 1] = a[x] == b[y] ? table[x][y] + 1 : [table[x][y + 1], table[x + 1][y]].max
        end
      end
      table
    end
  end
end
