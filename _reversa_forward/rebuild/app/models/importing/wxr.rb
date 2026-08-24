# frozen_string_literal: true

require "nokogiri"

module Importing
  # A parser for WXR — "WordPress eXtended RSS", the format wp-admin/export.php writes
  # (wp-admin/includes/export.php:495-720) and the one Platform::Export already emits at
  # /console/tools/export.
  #
  # ⚠️ Why this exists at all. Modern wp-admin/import.php is NOT an importer: it is a list
  # of importer PLUGINS to install ("In previous versions of WordPress, all importers were
  # built-in. They have been turned into plugins", import.php:26). AD-01 removed the
  # extension system, so that shell has nothing to point at. The honest equivalent of the
  # screen is therefore the thing the screen used to reach — a real, built-in reader for
  # the export format this system itself produces. Import and Export are one round trip
  # here, not a link to a plugin directory.
  #
  # A PURE-RUBY LEAF, deliberately: it reads bytes and returns Structs. It touches no
  # model, no database and no surface, which is what lets Importing::Run own every
  # decision about what a parsed record MEANS (the same split lib/seeding/pipeline.rb
  # keeps between Seeding::Legacy and the pipeline).
  #
  # ── What is read ──────────────────────────────────────────────────────────────────
  # Channel level: title, link, description, wp:wxr_version, wp:base_site_url,
  #   wp:base_blog_url; wp:author blocks (export.php:429-438); wp:category, wp:tag and
  #   wp:term blocks (export.php:538-575).
  # Item level: title, link, pubDate, dc:creator, guid, description, content:encoded,
  #   excerpt:encoded, wp:post_id, wp:post_date, wp:post_date_gmt, wp:post_modified_gmt,
  #   wp:comment_status, wp:ping_status, wp:post_name, wp:status, wp:post_parent,
  #   wp:menu_order, wp:post_type, wp:post_password, wp:is_sticky, wp:attachment_url,
  #   <category domain= nicename=> term references, wp:postmeta and wp:comment
  #   (including wp:comment_parent, which is what makes threads reconstructible).
  #
  # ── Namespaces ────────────────────────────────────────────────────────────────────
  # The wp: namespace URI carries the WXR version (…/export/1.0/, /1.1/, /1.2/), so
  # matching on the URI would silently drop every element of an older file. Elements are
  # matched on PREFIX + local name instead, with the URI accepted as a synonym — and a
  # document whose prefixes were never declared (libxml leaves the colon in the node
  # name) is handled by the same two helpers. `content:encoded` and `excerpt:encoded`
  # differ ONLY by prefix, which is also why `remove_namespaces!` is not an option here.
  class Wxr
    # A document that is not WXR at all. Distinguished from "WXR we could not fully map":
    # the first is the user uploading the wrong file, the second is a data problem, and
    # the screen says different things about them.
    class MalformedError < StandardError; end

    WP_NAMESPACE_PREFIX = "http://wordpress.org/export/"

    # wp:author (export.php:429-438).
    Author = Struct.new(:id, :login, :email, :display_name, :first_name, :last_name,
                        keyword_init: true) do
      # What the mapping form shows and keys on. The login is the WXR's own identifier
      # for an author and is what dc:creator on each item refers to.
      def key = login.to_s
      def label = display_name.presence || login.to_s
    end

    # wp:category / wp:tag / wp:term (export.php:538-575). One shape for all three: the
    # three blocks differ only in which element names carry the slug and the name.
    Term = Struct.new(:id, :taxonomy, :slug, :parent_slug, :name, :description, :meta,
                      keyword_init: true)

    # <category domain="…" nicename="…">Name</category> — wxr_post_taxonomy(),
    # export.php:475. A REFERENCE from an item to a term, not a term definition; a WXR
    # may carry references to terms it never defines, and the importer creates those.
    TermRef = Struct.new(:domain, :nicename, :name, keyword_init: true)

    # wp:comment (export.php:694-712).
    Comment = Struct.new(:id, :author_name, :author_email, :author_url, :author_ip,
                         :date, :date_gmt, :content, :approved, :kind, :parent_id,
                         :user_id, :meta, keyword_init: true)

    # <item> (export.php:635-716).
    Item = Struct.new(:post_id, :title, :link, :pub_date, :creator, :guid, :description,
                      :content, :excerpt, :post_date, :post_date_gmt, :post_modified_gmt,
                      :comment_status, :ping_status, :post_name, :status, :post_parent,
                      :menu_order, :post_type, :post_password, :is_sticky, :attachment_url,
                      :terms, :meta, :comments, keyword_init: true) do
      def label = title.to_s.strip.presence || post_name.presence || "(no title)"
    end

    Document = Struct.new(:wxr_version, :title, :link, :description, :base_site_url,
                          :base_blog_url, :authors, :terms, :items, keyword_init: true) do
      def empty? = items.empty? && terms.empty? && authors.empty?

      # The distinct dc:creator logins the items actually reference, plus every declared
      # wp:author — the set the "Assign Authors" form has to offer a row for. An export
      # whose author block was stripped still needs one row per creator.
      def author_keys
        declared = authors.map(&:key)
        referenced = items.filter_map { |i| i.creator.presence }
        (declared + referenced).uniq.reject(&:empty?)
      end

      def author_for(key) = authors.find { |a| a.key == key }
    end

    # ── Entry point ───────────────────────────────────────────────────────────────
    def self.parse(source) = new(source).parse

    def initialize(source)
      @source = source.respond_to?(:read) ? source.read : source.to_s
    end

    def parse
      doc = Nokogiri::XML(@source) { |c| c.norecover.strict }
      raise MalformedError, "the file is not valid XML" if doc.root.nil?

      channel = doc.root.element_children.find { |n| local_name(n) == "channel" }
      raise MalformedError, "the file is not a WordPress eXtended RSS export" if channel.nil?

      Document.new(
        wxr_version: text(channel, "wp", "wxr_version"),
        title: text(channel, nil, "title"),
        link: text(channel, nil, "link"),
        description: text(channel, nil, "description"),
        base_site_url: text(channel, "wp", "base_site_url"),
        base_blog_url: text(channel, "wp", "base_blog_url"),
        authors: children(channel, "wp", "author").map { |n| author(n) },
        terms: terms(channel),
        items: children(channel, nil, "item").map { |n| item(n) }
      )
    rescue Nokogiri::XML::SyntaxError => e
      raise MalformedError, "the file is not valid XML (#{e.message})"
    end

    private

    # ── Channel-level blocks ─────────────────────────────────────────────────────

    def author(node)
      Author.new(
        id: integer(node, "wp", "author_id"),
        login: text(node, "wp", "author_login"),
        email: text(node, "wp", "author_email"),
        display_name: text(node, "wp", "author_display_name"),
        first_name: text(node, "wp", "author_first_name"),
        last_name: text(node, "wp", "author_last_name")
      )
    end

    # The three term blocks, in the order export.php writes them. `wp:category` and
    # `wp:tag` are shorthands for taxonomy `category` / `post_tag`; `wp:term` names its
    # taxonomy outright and is how everything else (including nav_menu) travels.
    def terms(channel)
      out = []
      children(channel, "wp", "category").each do |n|
        out << Term.new(id: integer(n, "wp", "term_id"), taxonomy: "category",
                        slug: text(n, "wp", "category_nicename"),
                        parent_slug: text(n, "wp", "category_parent"),
                        name: text(n, "wp", "cat_name"),
                        description: text(n, "wp", "category_description"),
                        meta: term_meta(n))
      end
      children(channel, "wp", "tag").each do |n|
        out << Term.new(id: integer(n, "wp", "term_id"), taxonomy: "post_tag",
                        slug: text(n, "wp", "tag_slug"), parent_slug: "",
                        name: text(n, "wp", "tag_name"),
                        description: text(n, "wp", "tag_description"),
                        meta: term_meta(n))
      end
      children(channel, "wp", "term").each do |n|
        out << Term.new(id: integer(n, "wp", "term_id"),
                        taxonomy: text(n, "wp", "term_taxonomy"),
                        slug: text(n, "wp", "term_slug"),
                        parent_slug: text(n, "wp", "term_parent"),
                        name: text(n, "wp", "term_name"),
                        description: text(n, "wp", "term_description"),
                        meta: term_meta(n))
      end
      out
    end

    def term_meta(node)
      children(node, "wp", "termmeta").to_h { |m| [text(m, "wp", "meta_key"), text(m, "wp", "meta_value")] }
    end

    # ── Items ────────────────────────────────────────────────────────────────────

    def item(node)
      Item.new(
        post_id: integer(node, "wp", "post_id"),
        title: text(node, nil, "title"),
        link: text(node, nil, "link"),
        pub_date: text(node, nil, "pubDate"),
        creator: text(node, "dc", "creator"),
        guid: text(node, nil, "guid"),
        description: text(node, nil, "description"),
        content: text(node, "content", "encoded"),
        excerpt: text(node, "excerpt", "encoded"),
        post_date: text(node, "wp", "post_date"),
        post_date_gmt: text(node, "wp", "post_date_gmt"),
        post_modified_gmt: text(node, "wp", "post_modified_gmt"),
        comment_status: text(node, "wp", "comment_status"),
        ping_status: text(node, "wp", "ping_status"),
        post_name: text(node, "wp", "post_name"),
        status: text(node, "wp", "status"),
        post_parent: integer(node, "wp", "post_parent"),
        menu_order: integer(node, "wp", "menu_order"),
        post_type: text(node, "wp", "post_type"),
        post_password: text(node, "wp", "post_password"),
        is_sticky: text(node, "wp", "is_sticky") == "1",
        attachment_url: text(node, "wp", "attachment_url"),
        terms: children(node, nil, "category").map { |c| term_ref(c) },
        meta: post_meta(node),
        comments: children(node, "wp", "comment").map { |c| comment(c) }
      )
    end

    def term_ref(node)
      TermRef.new(domain: node["domain"].to_s, nicename: node["nicename"].to_s,
                  name: node.text.to_s.strip)
    end

    # ⚠️ NOT a Hash. wp_postmeta is multi-valued by design (BR-MIGRATE-028), and
    # collapsing it here would destroy exactly the distinction AD-05's (post_id, key)
    # unique index exists to surface. Pairs in document order; the importer groups them.
    def post_meta(node)
      children(node, "wp", "postmeta").map { |m| [text(m, "wp", "meta_key"), text(m, "wp", "meta_value")] }
    end

    def comment(node)
      Comment.new(
        id: integer(node, "wp", "comment_id"),
        author_name: text(node, "wp", "comment_author"),
        author_email: text(node, "wp", "comment_author_email"),
        author_url: text(node, "wp", "comment_author_url"),
        author_ip: text(node, "wp", "comment_author_IP"),
        date: text(node, "wp", "comment_date"),
        date_gmt: text(node, "wp", "comment_date_gmt"),
        content: text(node, "wp", "comment_content"),
        approved: text(node, "wp", "comment_approved"),
        kind: text(node, "wp", "comment_type"),
        parent_id: integer(node, "wp", "comment_parent"),
        user_id: integer(node, "wp", "comment_user_id"),
        meta: children(node, "wp", "commentmeta")
                .to_h { |m| [text(m, "wp", "meta_key"), text(m, "wp", "meta_value")] }
      )
    end

    # ── Prefix-aware element access ──────────────────────────────────────────────
    #
    # `prefix` nil selects an UNPREFIXED element, which is a real distinction here:
    # <category> at item level is a term reference in no namespace, while
    # <wp:category> at channel level is a term definition.

    def children(node, prefix, name)
      node.element_children.select { |c| local_name(c) == name && prefix_name(c) == prefix }
    end

    def text(node, prefix, name)
      found = children(node, prefix, name).first
      return "" if found.nil?

      # CDATA and plain text read the same through #text; wxr_cdata() only wraps when the
      # value would otherwise need escaping (export.php:294-302).
      found.text.to_s
    end

    def integer(node, prefix, name)
      raw = text(node, prefix, name)
      raw.strip.empty? ? nil : raw.to_i
    end

    # libxml resolves a DECLARED prefix into node.namespace and strips it from node.name;
    # an UNDECLARED one is left in the name verbatim. Both are answered here so a
    # hand-edited export missing an xmlns still parses.
    def prefix_name(node)
      declared = node.namespace
      if declared
        return declared.prefix if declared.prefix.present?
        # A default namespace on the element: unprefixed as far as WXR is concerned.
        return declared.href.to_s.start_with?(WP_NAMESPACE_PREFIX) ? "wp" : nil
      end
      node.name.include?(":") ? node.name.split(":", 2).first : nil
    end

    def local_name(node)
      node.name.include?(":") ? node.name.split(":", 2).last : node.name
    end
  end
end
