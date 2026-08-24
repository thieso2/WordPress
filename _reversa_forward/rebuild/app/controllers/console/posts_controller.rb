# frozen_string_literal: true

module Console
  # console.post-new / console.post — the editor SHELL (target_screens.md § The editor,
  # DEV-012). Origin: wp-admin/post-new.php and wp-admin/post.php, both of which include
  # wp-admin/edit-form-blocks.php.
  #
  # SCOPE: the React island (DEV-012, D-3) is BUILT (app/frontend/editor/*). This controller
  # is its server half: #edit renders the mount point + noscript fallback; #blocks hands the
  # island the parsed block tree; #update accepts either a JSON block tree (island) or raw
  # markup (fallback), serializing the tree SERVER-SIDE through Composition::Serializer — one
  # verified grammar — before the same Publishing::Post commands run in both paths.
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

    before_action :load_post, only: %i[edit update blocks autosave lock unlock steal]
    before_action :authorize_edit!, only: %i[edit update blocks autosave lock unlock steal]

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
      # The React island (DEV-012, D-3) PATCHes a JSON block tree; the noscript <form>
      # PATCHes raw markup. Both converge on the same Publishing::Post commands. The JSON
      # arm serializes the tree SERVER-SIDE through Composition::Serializer — the single,
      # already-verified grammar — so the editor's output cannot drift from the parser the
      # Wave 3 differential specs pinned against the live oracle.
      if request.format.json? || island_payload.present?
        return update_from_island
      end

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

    # GET /console/posts/:id/blocks — the island's initial load. Hands over the post's
    # content already parsed into the block tree (so the client shares the server's grammar
    # rather than re-parsing markup in JS) plus the document fields the canvas edits.
    def blocks
      render json: {
        id: @post.id,
        title: @post.title.to_s,
        excerpt: @post.excerpt.to_s,
        status: @post.status,
        published_at: @post.published_at&.iso8601,
        blocks: tree_json(Composition::Parser.parse(@post.content.to_s))
      }
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
    # The settings blob wp-admin hands initializeEditor (block_editor_settings_all()). Only a
    # truthful subset: whatever is NOT declared here the editor simply does without, which is
    # the honest failure mode — a fabricated capability would show a control that then breaks.
    # Everything data-shaped (post types, taxonomies, the user, global styles) is fetched by
    # core-data from our own wp/v2 API rather than inlined here.
    def editor_settings_json
      theme = Presentation::Theme.active.first
      {
        richEditingEnabled: true,
        codeEditingEnabled: true,
        # No custom-field UI: AD-03 promoted the core keys to columns and AD-01 removed the
        # registered-meta system the legacy's metabox wrote through.
        enableCustomFields: false,
        supportsLayout: true,
        # The theme's own theme.json settings, through the four-origin cascade the front end
        # already renders from — so the editor's palette IS the site's palette.
        __experimentalFeatures: theme_editor_features(theme),
        allowedMimeTypes: Library::Asset.try(:allowed_mime_types) || {},
        maxUploadFileSize: Platform::Storage.try(:max_upload_bytes) || 64.megabytes,
        imageSizes: [],
        # DEV-009: no WordPress-branded welcome guide or help links.
        canLockBlocks: true
      }.to_json
    end
    helper_method :editor_settings_json

    def theme_editor_features(theme)
      return {} if theme.nil?

      raw = (theme.resolver.merged_data.raw_data rescue nil)
      raw.is_a?(Hash) ? (raw["settings"] || {}) : {}
    rescue StandardError
      {}
    end


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

    # The parsed body of an island PATCH: { command, title, excerpt, published_at, blocks }.
    # Read from raw_post so arbitrary block attrs survive (strong-params would strip them);
    # the request is already authenticated (EditorAuthGate) and row-authorized.
    def island_payload
      return @island_payload if defined?(@island_payload)
      @island_payload =
        if request.content_type.to_s.include?("json") && request.raw_post.present?
          JSON.parse(request.raw_post) rescue nil
        end
    end

    def update_from_island
      if (holder = @post.edit_lock_holder_if_live(actor: current_actor))
        return render json: { ok: false, lock_error: {
          name: holder.display_name,
          text: format("%s has taken over and is currently editing.", holder.display_name)
        } }, status: :conflict
      end

      payload = island_payload || {}
      @post.actor = current_actor
      @post.title = payload["title"].to_s
      @post.excerpt = payload["excerpt"].to_s
      @post.content = Composition::Serializer.serialize(Array(payload["blocks"]))
      @command = payload["command"].to_s
      params[:published_at] = payload["published_at"] if payload.key?("published_at")
      apply_command!(@command)
      @post.lock_editing!(actor: current_actor)

      render json: {
        ok: true,
        status: @post.status,
        # The classic editor's own $messages snackbar copy (extractable half).
        notice: island_saved_notice,
        view_url: view_url_for(@post)
      }
    rescue ActiveRecord::RecordInvalid => e
      render json: { ok: false, errors: e.record.errors.full_messages }, status: :unprocessable_content
    end

    # Parser::Block tree -> JSON-friendly hashes for the island. innerContent's nil markers
    # are preserved (serialize_block walks them); the client renders innerHTML and recurses
    # into innerBlocks, and hands the same shape back on save.
    def tree_json(blocks)
      blocks.map do |b|
        {
          name: b.block_name,
          attrs: b.attrs || {},
          innerHTML: b.inner_html.to_s,
          innerContent: b.inner_content,
          innerBlocks: tree_json(b.inner_blocks || [])
        }
      end
    end

    def island_saved_notice
      params[:command] = @command
      saved_notice
    end

    def view_url_for(post)
      return nil unless post.published? && post.slug.present?
      "/#{post.published_at&.strftime("%Y/%m")}/#{post.slug}"
    end

    # edit-form-advanced.php:185 `__( 'Post scheduled for: %s.' )`. The strong-wrapped date
    # is the legacy's; here the instant the model settled on (published_at) fills it.
    def scheduled_message(noun)
      format("#{noun} scheduled for: %s.", @post.published_at&.strftime("%b %-d, %Y @ %H:%M"))
    end
  end
end
