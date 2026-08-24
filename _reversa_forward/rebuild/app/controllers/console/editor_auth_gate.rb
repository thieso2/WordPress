# frozen_string_literal: true

module Console
  # auth_redirect() (wp-includes/pluggable.php, called at wp-admin/admin.php:104): the
  # console's single authentication gate. An unauthenticated request to any admin URL is
  # bounced to the login screen with a `redirect_to` back to where it was headed
  # (wp_login_url( $redirect, true ), :67), and the browser returns after signing in.
  #
  # The editor screens carry their OWN layout (EditorLayout, full-bleed) rather than the
  # console chrome, so they do not descend from the shared Console::BaseController; this
  # concern gives them the same front gate without that inheritance. AUTHORIZATION (which
  # capability the actor must hold) is a separate matter, declared per route under AD-04
  # and evaluated on the loaded record inside the controller — this concern only answers
  # "is there an actor at all", which is what auth_redirect() answers.
  module EditorAuthGate
    extend ActiveSupport::Concern
    include Auth::SessionCookie

    included do
      # ⚠️ PREPEND: auth_redirect() runs at wp-admin/admin.php:104, BEFORE any capability
      # check. ApplicationController's inherited `enforce_authorization_declaration` would
      # otherwise run first and answer an unauthenticated request with 403 — but the legacy
      # bounces it to the login screen instead. Prepending puts the identity gate ahead of
      # the authorization gate, so "no session" → login redirect and "session, wrong cap" →
      # forbidden, each as the legacy does.
      prepend_before_action :auth_redirect
    end

    private

    # wp-includes/pluggable.php `auth_redirect()`: no valid session → the login URL with a
    # `redirect_to` back to the requested URI (:64-71). GET only; a console request is a
    # navigation, and BR-AUTH-08's POST grace is already applied inside current_session.
    def auth_redirect
      return if current_actor.present?

      redirect_to login_path(redirect_to: request.fullpath)
    end
  end
end
