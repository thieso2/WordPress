# frozen_string_literal: true

require "rails_helper"

# AD-08: the oracle is the ground truth, so the fixture this parser is judged against is
# not hand-typed — it is the ORACLE'S OWN EXPORT, captured verbatim:
#
#   php -r 'require ".../tools/_bootstrap.php";
#           require ABSPATH."wp-admin/includes/export.php";
#           ob_start(); export_wp(array("content"=>"all")); …'
#
# on the live WordPress 7.2-alpha-63330 corpus (2026-08-24). 149 KB, 37 items across 12
# post types, three authors, five categories (hierarchical), four tags (one with an
# emoji in its slug), a nav_menu term, PHP-serialized term meta and ten comments threaded
# three deep. Nothing in it was authored for the test, which is the point: a parser
# tested against a fixture its own author wrote proves only that the author was
# consistent.
RSpec.describe Importing::Wxr do
  let(:oracle_wxr) { Rails.root.join("spec/fixtures/wxr/oracle_export.xml").read }
  let(:document) { described_class.parse(oracle_wxr) }

  describe "the channel" do
    it "reads the WXR version and the site identity" do
      expect(document.wxr_version).to eq("1.2")
      expect(document.base_site_url).to eq("http://127.0.0.1:8099")
      expect(document.base_blog_url).to eq("http://127.0.0.1:8099")
      # The title carries the corpus's deliberate quoting/emoji hazard, decoded from the
      # numeric entities bloginfo_rss() writes.
      expect(document.title).to include("Reversa Oracle")
      expect(document.title).to include("😀")
    end

    it "reads every wp:author block" do
      expect(document.authors.map(&:login)).to contain_exactly("oracle_admin", "oracle_editor", "oracle_author")
      author = document.authors.find { |a| a.login == "oracle_author" }
      expect(author.id).to eq(4)
      expect(author.email).to eq("oracle_author@example.com")
      # CDATA with an apostrophe, a double quote and an astral character in one value.
      expect(author.display_name).to eq(%(Author O'Brien "the tester" 😀))
      expect(author.first_name).to eq("Ünïcødé")
      expect(author.last_name).to eq("")
    end

    it "reads wp:category, wp:tag and wp:term into one term shape" do
      by_slug = document.terms.index_by(&:slug)

      expect(by_slug["top-category"].taxonomy).to eq("category")
      expect(by_slug["top-category"].id).to eq(2)
      expect(by_slug["top-category"].name).to eq("Top « Category » 😀")
      expect(by_slug["top-category"].parent_slug).to eq("")

      # wp:category_parent names the parent's SLUG, not its id (export.php:551).
      expect(by_slug["middle-category"].parent_slug).to eq("top-category")
      expect(by_slug["leaf-category"].parent_slug).to eq("middle-category")

      expect(by_slug["flat-tag-one"].taxonomy).to eq("post_tag")
      # A slug carrying a percent-encoded astral character survives byte for byte.
      expect(by_slug.keys).to include("tag-with-%f0%9f%98%80-emoji")

      # wp:term names its own taxonomy; nav_menu and wp_theme travel that way.
      expect(document.terms.map(&:taxonomy)).to include("nav_menu")
    end

    it "reads wp:termmeta, including a PHP-serialized payload, verbatim" do
      top = document.terms.find { |t| t.slug == "top-category" }
      expect(top.meta.keys).to include("oracle_serialized")
      expect(top.meta["oracle_serialized"]).to start_with("a:11:{")
    end
  end

  describe "items" do
    it "reads every item, of every post type" do
      expect(document.items.length).to eq(37)
      expect(document.items.map(&:post_type).tally).to include(
        "post" => 16, "page" => 6, "attachment" => 3, "nav_menu_item" => 3
      )
    end

    it "reads the full item shape for a published post" do
      hello = document.items.find { |i| i.post_name == "hello-world" }

      expect(hello.post_id).to eq(1)
      expect(hello.title).to eq("Hello world!")
      expect(hello.creator).to eq("oracle_admin")
      expect(hello.status).to eq("publish")
      expect(hello.post_type).to eq("post")
      expect(hello.post_parent).to eq(0)
      expect(hello.menu_order).to eq(0)
      expect(hello.comment_status).to eq("open")
      expect(hello.ping_status).to eq("open")
      expect(hello.post_date_gmt).to eq("2026-03-15 09:59:00")
      expect(hello.post_modified_gmt).to eq("2026-03-15 09:59:00")
      expect(hello.guid).to eq("http://127.0.0.1:8099/?p=1")
      expect(hello.is_sticky).to be(false)
      expect(hello.post_password).to eq("")
      # content:encoded and excerpt:encoded differ ONLY by namespace prefix, which is
      # exactly why remove_namespaces! is not an option in the parser.
      expect(hello.content).to include("<!-- wp:paragraph -->")
      expect(hello.excerpt).to eq("")
    end

    it "reads <category domain= nicename=> term references off an item" do
      hello = document.items.find { |i| i.post_name == "hello-world" }
      ref = hello.terms.first
      expect(ref.domain).to eq("category")
      expect(ref.nicename).to eq("uncategorized")
      expect(ref.name).to eq("Uncategorized")
    end

    it "keeps wp:postmeta as ORDERED PAIRS, not a hash" do
      # BR-MIGRATE-028: postmeta is multi-valued by design, and collapsing it into a Hash
      # here would destroy the very distinction AD-05's (post_id, key) unique index
      # exists to surface.
      with_meta = document.items.find { |i| i.meta.length > 1 }
      expect(with_meta.meta).to all(be_an(Array).and(have_attributes(length: 2)))
    end

    it "reads an attachment's wp:attachment_url" do
      attachment = document.items.find { |i| i.post_type == "attachment" }
      expect(attachment.attachment_url).to start_with("http://127.0.0.1:8099/wp-content/uploads/")
    end
  end

  describe "comments" do
    it "reads every comment, with the parent that makes a thread reconstructible" do
      comments = document.items.flat_map(&:comments)
      expect(comments.length).to eq(10)

      first = comments.find { |c| c.id == 1 }
      expect(first.author_name).to eq("A WordPress Commenter")
      expect(first.author_email).to eq("wapuu@wordpress.example")
      expect(first.author_url).to eq("https://wordpress.org/")
      expect(first.approved).to eq("1")
      expect(first.kind).to eq("comment")
      expect(first.parent_id).to eq(0)
      expect(first.content).to include("Hi, this is a comment.")

      # The corpus threads three deep; wp:comment_parent is what carries it.
      parents = comments.map(&:parent_id).reject(&:zero?)
      expect(parents).to contain_exactly(2, 3, 4)
    end
  end

  describe "the author roster the mapping form needs" do
    it "unions the declared authors with every dc:creator the items reference" do
      expect(document.author_keys).to include("oracle_admin", "oracle_editor", "oracle_author")
      expect(document.author_for("oracle_editor").label).to eq(%(Editor O'Brien "the tester" 😀))
    end
  end

  describe "refusals" do
    it "refuses a file that is not XML at all" do
      expect { described_class.parse("this is not xml") }
        .to raise_error(described_class::MalformedError)
    end

    it "refuses well-formed XML that is not WXR" do
      expect { described_class.parse("<?xml version='1.0'?><catalogue><book/></catalogue>") }
        .to raise_error(described_class::MalformedError, /not a WordPress eXtended RSS export/)
    end

    it "reads a WXR 1.0 document, whose wp: namespace URI carries a different version" do
      # Matching on the namespace URI would silently drop every element of an older file,
      # so the parser matches on prefix + local name instead.
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"
             xmlns:dc="http://purl.org/dc/elements/1.1/"
             xmlns:excerpt="http://wordpress.org/export/1.0/excerpt/"
             xmlns:wp="http://wordpress.org/export/1.0/">
          <channel>
            <title>Old</title>
            <wp:wxr_version>1.0</wp:wxr_version>
            <item>
              <title>Ancient</title>
              <wp:post_id>7</wp:post_id>
              <wp:status>publish</wp:status>
              <content:encoded><![CDATA[body]]></content:encoded>
            </item>
          </channel>
        </rss>
      XML
      doc = described_class.parse(xml)
      expect(doc.wxr_version).to eq("1.0")
      expect(doc.items.first.post_id).to eq(7)
      expect(doc.items.first.content).to eq("body")
      # WXR 1.0 has no wp:post_type; wp_insert_post()'s default applies at import time.
      expect(doc.items.first.post_type).to eq("")
    end
  end
end
