# frozen_string_literal: true

module Console
  # console.post-new / console.post — the editor SHELL (target_screens.md § The editor,
  # DEV-012). Origin: wp-admin/post-new.php and wp-admin/post.php, both of which include
  # wp-admin/edit-form-blocks.php.
  #
  # ⚠️ SCOPE (owner ruling, this pass): the Gutenberg CANVAS and INSPECTOR are the React
  # island DEV-012 defers — `deferred: react-island (DEV-012, D-3)`. This controller builds
  # the server-side half DEV-012 § server_side enumerates, all of which already exists as
  # models, and wires it to an HONEST placeholder canvas (a <textarea> over the post's raw
  # block markup, saving through the real command path). It does NOT fake the block editor.
  #
  # Everything below is a thin surface over Publishing::Post's commands — the same commands
  # the Wave 3 differential specs already verified against the live oracle. The controller
  # adds only what the editor screen adds: the auth gate, per-record authorization, the
  # edit lock, and the mapping from the shell's Save Draft / Publish / Schedule controls to
  # publish!/schedule!/update!.
  class PostsController < ApplicationController
    include Console::EditorAuthGate

    layout "editor"

    # The two content subtypes the editor opens. AD-02: STI over content types only; the
    # ten storage-tenancy `post_type`s the legacy also kept in wp_posts are not here.
    TYPES = { "post" => Publishing::Article, "page" => Publishing::Page }.freeze
    private_constant :TYPES

    # wp-admin/edit-form-blocks.php:281 / :275 — the editor's own placeholders, readable
    # from PHP (the surrounding canvas is not). Used on the placeholder textarea so the
    # shell is furnished with the legacy's own words, not invented ones.
    TITLE_PLACEHOLDER = "Add title"
    BODY_PLACEHOLDER = "Type / to choose a block"

    before_action :load_post, only: %i[edit update autosave lock unlock steal]
    before_action :authorize_edit!, only: %i[edit update autosave lock unlock steal]

    # GET /console/posts/new — get_default_post_to_edit( $post_type, true )
    # (wp-admin/includes/post.php:14-33): the legacy INSERTS an auto-draft immediately and
    # opens the editor on it, so autosave, revisions and the lock all have a real row to
    # hang on. The same here: create the auto_draft, then open its edit screen.
    def new
      klass = TYPES.fetch(params[:post_type].to_s, Publishing::Article)
      post = klass.new(author: current_actor, status: :auto_draft, title: "", content: "", excerpt: "")
      # create_posts, mapped through the record's own policy (auto_draft, owned by the
      # actor → edit_posts). A user who cannot create is refused before a row is written.
      unless Access::PostPolicy.for(current_actor, post).permit?(:edit)
        return head :forbidden
      end

      post.actor = current_actor
      post.save!
      redirect_to edit_console_post_path(post), status: :see_other
    end

    # GET /console/posts/:id/edit — wp-admin/post.php `case 'edit'` (:161-214), which runs
    # wp_check_post_lock() and, when another editor holds a live lock, shows the takeover
    # notice INSTEAD of acquiring one (_admin_notice_post_locked(), includes/post.php).
    def edit
      @holder = @post.edit_lock_holder_if_live(actor: current_actor)
      if @holder
        render :locked, status: :ok
      else
        @post.lock_editing!(actor: current_actor)
        render :edit
      end
    end

    # PATCH/PUT /console/posts/:id — the Save Draft / Publish / Schedule / Pending controls.
    # wp-admin/post.php `case 'editpost'` → edit_post() → wp_update_post(). A save by anyone
    # but the lock holder is refused, as the legacy's locked editor is read-only.
    def update
      if (@holder = @post.edit_lock_holder_if_live(actor: current_actor))
        return render :locked, status: :conflict
      end

      @post.actor = current_actor
      @post.assign_attributes(content_params)
      apply_command!(params[:command].to_s)
      @post.lock_editing!(actor: current_actor)
      redirect_to edit_console_post_path(@post), status: :see_other, notice: saved_notice
    rescue ActiveRecord::RecordInvalid => e
      @errors = e.record.errors.full_messages
      @holder = nil
      render :edit, status: :unprocessable_content
    end

    # POST /console/posts/:id/autosave — wp_create_post_autosave() via the heartbeat
    # (wp-admin/includes/post.php:1957). One autosave per author, overwritten in place;
    # an autosave equal to the record deletes itself and returns nil (Post#autosave!).
    def autosave
      revision = @post.autosave!(
        title: params[:title].to_s, content: params[:content].to_s,
        excerpt: params[:excerpt].to_s, actor: current_actor
      )
      render json: {
        success: true,
        autosave_id: revision&.id,
        # edit-form-blocks.php:140 (LITERAL) — the editor's own "saved" line.
        message: revision ? "Your latest changes were saved as a revision." : nil
      }
    end

    # POST /console/posts/:id/lock — wp_refresh_post_lock() (wp-admin/includes/misc.php
    # :1189), the heartbeat's lock tick. If another editor has taken over, answer with the
    # lock_error the legacy sends (:1207-1210, LITERAL); otherwise refresh our own lock and
    # return the new stamp (:1221-1225).
    def lock
      holder = @post.edit_lock_holder_if_live(actor: current_actor)
      if holder
        render json: { lock_error: {
          name: holder.display_name,
          text: format("%s has taken over and is currently editing.", holder.display_name)
        } }
      else
        stamp = @post.lock_editing!(actor: current_actor)
        render json: { new_lock: "#{stamp.first.to_i}:#{current_actor.id}" }
      end
    end

    # DELETE /console/posts/:id/lock — leave the editor. A target nicety over the legacy
    # (which let the 150 s window lapse); only the holder may release. See Post#release_lock!.
    def unlock
      @post.release_lock!(actor: current_actor)
      head :no_content
    end

    # POST /console/posts/:id/steal — the "Take over" button, wp-admin/post.php's
    # `get-post-lock` handler: it calls wp_set_post_lock() for the arriving user, seizing
    # the lock. Then the editor opens as normal.
    def steal
      @post.steal_lock!(actor: current_actor)
      redirect_to edit_console_post_path(@post), status: :see_other
    end

    private

    def load_post
      @post = Publishing::Post.find(params[:id])
      editor_chrome!
    end

    # The screen's <title>/<h1> and its identity. wp-admin/post.php:184 uses the post type's
    # `edit_item` label ("Edit Post" / "Edit Page", class-wp-post-type.php:991); post-new.php
    # :54 uses `add_new_item` ("Add Post" / "Add Page", :990). An auto_draft has never been
    # saved by the author, so it is still the "add" screen (console.post-new); anything else
    # is "edit" (console.post). Both strings are LITERAL.
    def editor_chrome!
      noun = @post.is_a?(Publishing::Page) ? "Page" : "Post"
      if @post.auto_draft?
        @title = "Add #{noun}"
        @screen = "console.post-new"
      else
        @title = "Edit #{noun}"
        @screen = "console.post"
      end
    end

    # current_user_can( 'edit_post', $id ) through the record's own capability family
    # (Access::PostPolicy / PagePolicy). The AD-04 declaration gates the surface on
    # identity (:authenticated); the row-level arm is evaluated here, on the loaded record.
    def authorize_edit!
      return if Access::PostPolicy.for(current_actor, @post).permit?(:edit)

      head :forbidden
    end

    def content_params
      params.permit(:title, :content, :excerpt)
    end

    # The shell's control strip → Publishing::Post's commands. The verbs are the caller's
    # intent; the model decides the resulting status (BR-MIGRATE-029/030 for publish, the
    # 60-second threshold; slug allocation on first publish, BR-MIGRATE-032, is automatic).
    def apply_command!(command)
      case command
      when "publish"
        @post.publish!(actor: current_actor)
      when "schedule"
        @post.schedule!(at: scheduled_at, actor: current_actor)
      when "pending"
        @post.update!(status: :pending)
      else # "draft" / "save" / anything else: Save Draft. auto_draft promotes to draft.
        @post.status = :draft if @post.auto_draft?
        @post.save!
      end
    end

    def scheduled_at
      Time.zone.parse(params[:published_at].to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # The classic editor's own `$messages` (wp-admin/edit-form-advanced.php:172-200,
    # LITERAL) — the readable half of the editor's copy, keyed by post vs page. The block
    # editor shows the same wording in a JS snackbar this checkout cannot read, so these
    # extracted strings are the truthful source for the shell's save feedback.
    def saved_notice
      noun = @post.is_a?(Publishing::Page) ? "Page" : "Post"
      case params[:command].to_s
      when "publish"
        @post.scheduled? ? scheduled_message(noun) : "#{noun} published."          # :181 / :196
      when "schedule"
        scheduled_message(noun)                                                     # :185 / :200
      when "pending"
        "#{noun} updated."                                                          # :175 / :190
      else
        "#{noun} draft updated."                                                    # :186 / :10
      end
    end

    # edit-form-advanced.php:185 `__( 'Post scheduled for: %s.' )`. The strong-wrapped date
    # is the legacy's; here the instant the model settled on (published_at) fills it.
    def scheduled_message(noun)
      format("#{noun} scheduled for: %s.", @post.published_at&.strftime("%b %-d, %Y @ %H:%M"))
    end
  end
end
