# frozen_string_literal: true

require "builder"

module Platform
  # console.export — wp-admin/export.php's WXR writer (export_wp(),
  # wp-admin/includes/export.php), reduced to the content this system holds. WXR is
  # "WordPress eXtended RSS": an RSS 2.0 document in the wxr/excerpt/content/wfw
  # namespaces carrying posts, pages, comments and terms so another install can import
  # them (export.php:176-178, the LITERAL description on the screen).
  #
  # A pure-Ruby leaf: reads Publishing / Classification / Identity, depends on no
  # surface. Menus and the eleven machinery post types AD-02 split out of `posts` are out
  # of scope and named as such on the screen — an honest subset beats a fake completeness.
  #
  # ⚠️ 2026-08-24 — the fields below the first block were added when console.import was
  # built (Importing::Wxr / Importing::Run). Export and Import are ONE round trip: an
  # export that omits wp:post_parent, wp:menu_order, the per-item
  # `<category domain= nicename=>` references, wp:postmeta or wp:comment_parent cannot be
  # re-imported without silently flattening the hierarchy, the taxonomy, the custom fields
  # and the comment threads. Every element added here is export.php's own
  # (wp-admin/includes/export.php:495-720) and is written in that file's order, so what
  # this system emits stays a WXR another WordPress can read.
  module Export
    WXR_VERSION = "1.2"

    module_function

    # ⚠️ CDATA is written LITERALLY rather than through `xml.tag!(name) { xml.cdata!(v) }`.
    # Builder pretty-prints the contents of a block, which injects a newline and the
    # element's indentation INSIDE the CDATA section — i.e. it changes the value. That is
    # invisible until something reads the file back, at which point every excerpt, title
    # and comment body has grown whitespace; console.import's round-trip spec is what
    # surfaced it. The `]]>` escape is Builder's own (`]]]]><![CDATA[>`).
    def cdata_tag(xml, name, value)
      # ⚠️ A leading newline, and no indentation: Builder is a BlankSlate, so its
      # `_indent`/`_newline` cannot be reached through `send` (method_missing turns the
      # call into a `<send:_newline/>` element — observed). export.php's own output is
      # not uniformly indented either; what matters is that the CDATA is exact.
      xml << "\n<#{name}><![CDATA[#{value.to_s.gsub("]]>", "]]]]><![CDATA[>")}]]></#{name}>"
    end

    def wxr(site_url:, site_name:, site_description:)
      out = +""
      xml = Builder::XmlMarkup.new(target: out, indent: 2)
      xml.instruct!(:xml, version: "1.0", encoding: "UTF-8")
      xml.rss(
        version: "2.0",
        "xmlns:excerpt" => "http://wordpress.org/export/#{WXR_VERSION}/excerpt/",
        "xmlns:content" => "http://purl.org/rss/1.0/modules/content/",
        "xmlns:wfw" => "http://wellformedweb.org/CommentAPI/",
        "xmlns:dc" => "http://purl.org/dc/elements/1.1/",
        "xmlns:wp" => "http://wordpress.org/export/#{WXR_VERSION}/"
      ) do
        xml.channel do
          xml.title site_name
          xml.link site_url
          xml.description site_description
          xml.pubDate Time.current.rfc822
          xml.language "en-US"
          xml.tag!("wp:wxr_version", WXR_VERSION)
          xml.tag!("wp:base_site_url", site_url)
          xml.tag!("wp:base_blog_url", site_url)

          authors.each { |user| write_author(xml, user) }
          terms.each { |term| write_term(xml, term) }
          items.each { |post| write_item(xml, post, site_url) }
        end
      end
      out
    end

    def terms
      Classification::Term.includes(:taxonomy, :parent).order(:id).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    # wxr_authors_list(), export.php:405-441: "SELECT DISTINCT post_author FROM posts" —
    # the authors of the exported CONTENT, not every account on the site.
    def authors
      Identity::User.where(id: items.map(&:author_id).compact.uniq).order(:id).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    def write_author(xml, user)
      xml.tag!("wp:author") do
        xml.tag!("wp:author_id", user.id)
        cdata_tag(xml, "wp:author_login", user.login)
        cdata_tag(xml, "wp:author_email", user.email)
        cdata_tag(xml, "wp:author_display_name", user.display_name)
        cdata_tag(xml, "wp:author_first_name", user.try(:first_name))
        cdata_tag(xml, "wp:author_last_name", user.try(:last_name))
      end
    end

    # Posts and pages, newest first — the content export.php walks.
    def items
      Publishing::Post.where(status: %w[published private draft pending])
                      .order(published_at: :desc, id: :desc).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    # export.php:538-575. `category` and `post_tag` have shorthand blocks of their own;
    # every OTHER taxonomy travels as `wp:term`, which names its taxonomy outright. The
    # parent is written as the parent's SLUG, not its id (:551, :568) — an id belongs to
    # the site that wrote the file and an importer must not trust it.
    def write_term(xml, term)
      case term.taxonomy&.name
      when "post_tag"
        xml.tag!("wp:tag") do
          xml.tag!("wp:term_id", term.id)
          cdata_tag(xml, "wp:tag_slug", term.slug)
          cdata_tag(xml, "wp:tag_name", term.name)
          cdata_tag(xml, "wp:tag_description", term.description) if term.description.present?
        end
      when "category", nil
        xml.tag!("wp:category") do
          xml.tag!("wp:term_id", term.id)
          cdata_tag(xml, "wp:category_nicename", term.slug)
          cdata_tag(xml, "wp:category_parent", term.parent&.slug)
          cdata_tag(xml, "wp:cat_name", term.name)
          cdata_tag(xml, "wp:category_description", term.description) if term.description.present?
        end
      else
        xml.tag!("wp:term") do
          xml.tag!("wp:term_id", term.id)
          cdata_tag(xml, "wp:term_taxonomy", term.taxonomy.name)
          cdata_tag(xml, "wp:term_slug", term.slug)
          cdata_tag(xml, "wp:term_parent", term.parent&.slug)
          cdata_tag(xml, "wp:term_name", term.name)
          cdata_tag(xml, "wp:term_description", term.description) if term.description.present?
        end
      end
    end

    # export.php:635-716, in that file's element order.
    def write_item(xml, post, site_url)
      stamp = post.published_at || post.created_at
      xml.item do
        xml.title post.title.to_s
        xml.link "#{site_url}/?p=#{post.id}"
        xml.pubDate stamp.rfc822
        cdata_tag(xml, "dc:creator", post.author&.login)
        xml.guid("#{site_url}/?p=#{post.id}", isPermaLink: "false")
        xml.description ""
        cdata_tag(xml, "content:encoded", post.content)
        cdata_tag(xml, "excerpt:encoded", post.excerpt)
        xml.tag!("wp:post_id", post.id)
        xml.tag!("wp:post_date", stamp.strftime("%Y-%m-%d %H:%M:%S"))
        # AD-07: the *_gmt column IS the single timestamptz here, so the GMT element is
        # the one an importer should trust — and the one Importing::Run reads first.
        xml.tag!("wp:post_date_gmt", stamp.utc.strftime("%Y-%m-%d %H:%M:%S"))
        xml.tag!("wp:post_modified_gmt", post.modified_at.utc.strftime("%Y-%m-%d %H:%M:%S"))
        xml.tag!("wp:comment_status", post.comment_status.to_s)
        # AD-03 dropped ping_status as a column; the corpus's value is parked in the
        # residual bucket (Publishing::Post#residual_attributes), so it round-trips.
        xml.tag!("wp:ping_status", post.residual_attributes["ping_status"].presence || "closed")
        xml.tag!("wp:post_name", post.slug.to_s)
        xml.tag!("wp:status", legacy_status(post))
        xml.tag!("wp:post_parent", post.parent_id.to_i)
        xml.tag!("wp:menu_order", post.menu_order.to_i)
        xml.tag!("wp:post_type", post.is_a?(Publishing::Page) ? "page" : "post")
        # ⚠️ NOT the password. `posts.password_digest` is a bcrypt digest here (the legacy
        # stored plaintext, and T-09 refused to copy it into a column named `_digest`);
        # writing it into a WXR would publish the digest and would not import as a
        # password anyway. Emitted empty, as it is for every unprotected record.
        xml.tag!("wp:post_password", "")
        xml.tag!("wp:is_sticky", 0)
        terms_for(post).each { |term| write_term_reference(xml, term) }
        attributes_for(post).each { |key, value| write_postmeta(xml, key, value) }
        comments_for(post).each { |c| write_comment(xml, c) }
      end
    end

    # T-05/post_status in reverse. The enum's names are this system's; a WXR carries the
    # legacy's, and an importer on any WordPress will only recognise those.
    LEGACY_STATUS = { "published" => "publish", "scheduled" => "future",
                      "trashed" => "trash", "auto_draft" => "auto-draft" }.freeze

    def legacy_status(post) = LEGACY_STATUS.fetch(post.status.to_s, post.status.to_s)

    # wxr_post_taxonomy(), export.php:463-477.
    def terms_for(post)
      Classification::Term.includes(:taxonomy)
                          .where(id: Classification::Assignment
                                       .where(classifiable_type: "Publishing::Post", classifiable_id: post.id)
                                       .select(:term_id))
                          .order(:id).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    def write_term_reference(xml, term)
      xml << %(\n<category domain="#{ERB::Util.html_escape(term.taxonomy&.name)}" nicename="#{ERB::Util.html_escape(term.slug)}"><![CDATA[#{term.name.to_s.gsub("]]>", "]]]]><![CDATA[>")}]]></category>)
    end

    # AD-03/AD-05: the residual bucket has two storage shapes, and BOTH are postmeta as
    # far as a WXR is concerned — a multi-valued key is simply several wp:postmeta
    # elements sharing a key, which is how it arrived.
    def attributes_for(post)
      pairs = Publishing::Attribute.where(post_id: post.id).order(:key)
                                   .map { |a| [a.key, encode_meta(a.value)] }
      post.residual_attributes.except("ping_status").each do |key, values|
        Array.wrap(values).each { |v| pairs << [key, encode_meta(v)] }
      end
      pairs
    rescue ActiveRecord::StatementInvalid
      []
    end

    # ⚠️ `post_attributes.value` is jsonb holding a JSON DOCUMENT — the seeding pipeline's
    # convention (`Publishing::Attribute.create!(value: decoded.to_json)`), which
    # Importing::Run follows so the two loaders store a custom field the same way. So the
    # value read back from a scalar row is JSON TEXT (`"kept"`, quotes included), and
    # emitting it raw would export the quotes and re-import them a level deeper every
    # round trip. It is decoded here, once, back to the value the legacy's meta_value held.
    #
    # A structured value (the multi-valued residual bucket, AD-03) has no PHP serialize()
    # form this system can produce, so it goes out as JSON text and comes back as a JSON
    # string rather than as a structure — a stated asymmetry of the pair, not a silent one.
    def encode_meta(value)
      decoded = value.is_a?(String) ? (JSON.parse(value, quirks_mode: true) rescue value) : value
      case decoded
      when String, Numeric, true, false, nil then decoded.to_s
      else decoded.to_json
      end
    end

    def write_postmeta(xml, key, value)
      xml.tag!("wp:postmeta") do
        cdata_tag(xml, "wp:meta_key", key)
        cdata_tag(xml, "wp:meta_value", value)
      end
    end

    # export.php:694-712. wp:comment_parent is what makes a THREAD survive the round
    # trip; without it every reply re-imports as a top-level comment.
    LEGACY_COMMENT_STATUS = { "approved" => "1", "pending" => "0",
                              "spam" => "spam", "trashed" => "trash" }.freeze

    def write_comment(xml, comment)
      xml.tag!("wp:comment") do
        xml.tag!("wp:comment_id", comment.id)
        cdata_tag(xml, "wp:comment_author", comment.author_name)
        xml.tag!("wp:comment_author_email", comment.author_email.to_s)
        xml.tag!("wp:comment_author_url", comment.author_url.to_s)
        xml.tag!("wp:comment_author_IP", comment.author_ip.to_s)
        xml.tag!("wp:comment_date", comment.submitted_at.strftime("%Y-%m-%d %H:%M:%S"))
        xml.tag!("wp:comment_date_gmt", comment.submitted_at.utc.strftime("%Y-%m-%d %H:%M:%S"))
        cdata_tag(xml, "wp:comment_content", comment.content)
        xml.tag!("wp:comment_approved", LEGACY_COMMENT_STATUS.fetch(comment.status.to_s, "0"))
        xml.tag!("wp:comment_type", comment.kind.to_s)
        xml.tag!("wp:comment_parent", comment.parent_id.to_i)
        xml.tag!("wp:comment_user_id", comment.user_id.to_i)
      end
    end

    # export.php:686: `comment_approved <> 'spam'`. Spam is not content and does not
    # travel. Ordered parent-first so a re-import resolves every thread in one pass.
    def comments_for(post)
      Discussion::Comment.where(post_id: post.id).where.not(status: "spam")
                         .order(Arel.sql("parent_id NULLS FIRST"), :submitted_at, :id).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end
  end
end
