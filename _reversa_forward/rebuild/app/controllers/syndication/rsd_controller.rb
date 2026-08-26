# frozen_string_literal: true

module Syndication
  # `/xmlrpc.php?rsd` — the Really Simple Discovery document (xmlrpc.php:31-63).
  #
  # ⚠️ This is a DISCOVERY document, not the XML-RPC server. `presentation/head.rb` prints
  # the RSD link in the <head> of every screen, so the site advertised this URL and answered
  # it with its own 404 — one of the 19 dead links bin/link_check found. Serving the document
  # is what closes that; the 78-method XML-RPC server behind `POST /xmlrpc.php` is a separate
  # protocol surface and is still unimplemented (gaps.md G-01 records the decision to keep
  # XML-RPC enabled; that decision is not yet carried out, and this does not carry it out).
  #
  # A GET without `rsd` is the legacy's own 405: xmlrpc.php only accepts POST, and the PHP
  # dev server answers `Allow: POST` exactly as wp-comments-post.php does.
  class RsdController < ApplicationController
    include LegacyHeaders

    def show
      # `isset( $_GET['rsd'] )` — PRESENCE, not truth. `?rsd`, `?rsd=` and `?rsd=0` all
      # take this arm; only a request without the parameter at all falls through.
      return method_not_allowed unless request.query_parameters.key?("rsd")

      render_with_legacy_content_type "syndication/rsd/show", formats: [:xml],
                                      content_type: "text/xml; charset=#{blog_charset}"
    end

    private

    # xmlrpc.php serves POST only; the legacy answers anything else with 405 + Allow: POST,
    # the same shape Web::CommentsController#method_not_allowed already reproduces.
    def method_not_allowed
      response.set_header("Allow", "POST")
      head :method_not_allowed
    end
  end
end
