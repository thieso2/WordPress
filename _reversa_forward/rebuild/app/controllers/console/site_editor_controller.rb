# frozen_string_literal: true

module Console
  # console.site-editor — wp-admin/site-editor.php. Origin loads the same block-editor
  # bundle as the post editor, scoped to templates, template parts and Global Styles across
  # the four-origin cascade (target_screens.md § The editor, spec.site_editor_additional).
  #
  # ⚠️ SCOPE (owner ruling, this pass): the entire site-editor UI — template/part browsing
  # and editing, and Global Styles editing — is the React island DEV-012 defers:
  # `deferred: react-island (DEV-012, D-3)`. The server-side substrate it edits already
  # exists (Composition::Template / Presentation, the theme.json cascade), but the editing
  # surface is not built this pass. This controller is the authenticated, authorized SHELL
  # with an honest placeholder, not a fake editor.
  class SiteEditorController < ApplicationController
    include Console::EditorAuthGate

    layout "editor"

    before_action :authorize_theme_options!

    # GET /console/site-editor. site-editor.php gates on `edit_theme_options`
    # (current_user_can), enforced by the AD-04 policy declaration and re-stated here.
    def show
      @templates = Composition::Template.where(kind: "template").order(:slug).to_a
    end

    private

    def authorize_theme_options!
      return if Access::SitePolicy.new(current_actor, nil).permit?(:edit_theme_options)

      head :forbidden
    end
  end
end
