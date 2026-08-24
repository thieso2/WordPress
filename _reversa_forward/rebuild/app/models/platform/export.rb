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
  # surface. Custom fields, postmeta and menus are out of this pass's scope and named as
  # such on the screen — an honest subset beats a fake completeness.
  module Export
    WXR_VERSION = "1.2"

    module_function

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

          terms.each { |term| write_term(xml, term) }
          items.each { |post| write_item(xml, post, site_url) }
        end
      end
      out
    end

    def terms
      Classification::Term.includes(:taxonomy).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    # Posts and pages, newest first — the content export.php walks.
    def items
      Publishing::Post.where(status: %w[published private draft pending])
                      .order(published_at: :desc, id: :desc).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end

    def write_term(xml, term)
      key = term.taxonomy&.name == "post_tag" ? "wp:tag" : "wp:category"
      xml.tag!(key) do
        xml.tag!("wp:term_id", term.id)
        xml.tag!(term.taxonomy&.name == "post_tag" ? "wp:tag_slug" : "wp:category_nicename", term.slug)
        name_key = term.taxonomy&.name == "post_tag" ? "wp:tag_name" : "wp:cat_name"
        xml.tag!(name_key) { xml.cdata!(term.name.to_s) }
      end
    end

    def write_item(xml, post, site_url)
      xml.item do
        xml.title post.title.to_s
        xml.link "#{site_url}/?p=#{post.id}"
        xml.pubDate (post.published_at || post.created_at).rfc822
        xml.tag!("dc:creator") { xml.cdata!(post.author&.login.to_s) }
        xml.guid("#{site_url}/?p=#{post.id}", isPermaLink: "false")
        xml.tag!("content:encoded") { xml.cdata!(post.content.to_s) }
        xml.tag!("excerpt:encoded") { xml.cdata!(post.excerpt.to_s) }
        xml.tag!("wp:post_id", post.id)
        xml.tag!("wp:post_date", (post.published_at || post.created_at).strftime("%Y-%m-%d %H:%M:%S"))
        xml.tag!("wp:post_name", post.slug.to_s)
        xml.tag!("wp:status", post.status.to_s)
        xml.tag!("wp:post_type", post.is_a?(Publishing::Page) ? "page" : "post")
        comments_for(post).each { |c| write_comment(xml, c) }
      end
    end

    def write_comment(xml, comment)
      xml.tag!("wp:comment") do
        xml.tag!("wp:comment_id", comment.id)
        xml.tag!("wp:comment_author") { xml.cdata!(comment.author_name.to_s) }
        xml.tag!("wp:comment_author_email", comment.author_email.to_s)
        xml.tag!("wp:comment_date", comment.submitted_at.strftime("%Y-%m-%d %H:%M:%S"))
        xml.tag!("wp:comment_content") { xml.cdata!(comment.content.to_s) }
        xml.tag!("wp:comment_approved", comment.status.to_s == "approved" ? "1" : "0")
      end
    end

    def comments_for(post)
      Discussion::Comment.where(post_id: post.id).order(:submitted_at).to_a
    rescue ActiveRecord::StatementInvalid
      []
    end
  end
end
