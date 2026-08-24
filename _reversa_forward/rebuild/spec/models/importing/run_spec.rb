# frozen_string_literal: true

require "rails_helper"

# The ETL itself, at the level the screen cannot reach: what happens to a record that
# CANNOT be mapped. lib/seeding/report.rb's rule is the one under test —
#
#   "The dead-letter queue must fail the run. A pipeline that quietly coerces bad input
#    into defaults would still fill the database, and would destroy exactly the signal
#    this step exists to produce."
#
# — so every case below asserts BOTH that the run reported the problem and that it wrote
# nothing plausible-looking in its place.
RSpec.describe Importing::Run do
  def wxr(items: "", channel: "")
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"
           xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/"
           xmlns:content="http://purl.org/rss/1.0/modules/content/"
           xmlns:dc="http://purl.org/dc/elements/1.1/"
           xmlns:wp="http://wordpress.org/export/1.2/">
        <channel>
          <title>Source</title>
          <wp:wxr_version>1.2</wp:wxr_version>
          #{channel}
          #{items}
        </channel>
      </rss>
    XML
  end

  def item(**overrides)
    fields = {
      "title" => "An item", "wp:post_id" => "10", "wp:post_name" => "an-item",
      "wp:status" => "publish", "wp:post_type" => "post",
      "wp:post_date_gmt" => "2026-01-02 03:04:05", "dc:creator" => "src_author",
      "wp:post_parent" => "0", "wp:menu_order" => "0"
    }.merge(overrides.transform_keys(&:to_s))
    body = fields.filter_map { |k, v| "<#{k}>#{v}</#{k}>" unless v.nil? }.join("\n")
    "<item>#{body}</item>"
  end

  def run!(xml, **options)
    described_class.new(Importing::Wxr.parse(xml), **options).call
  end

  describe "records that cannot be mapped" do
    it "REPORTS an unmapped wp:status instead of defaulting it to draft" do
      result = run!(wxr(items: item("wp:status" => "in_review")))

      expect(Publishing::Post.count).to eq(0)
      failure = result.records_for("post").first
      expect(failure.outcome).to eq(:failed)
      expect(failure.detail).to match(/unmapped post_status "in_review"/)
      expect(result).not_to be_clean
    end

    it "REPORTS a published item with no publication date rather than back-dating it to now" do
      # posts_published_at_present is a CHECK constraint: the row is unrepresentable, and
      # inventing `Time.current` would be inventing a publication date.
      result = run!(wxr(items: item("wp:post_date_gmt" => "0000-00-00 00:00:00", "pubDate" => nil)))

      expect(Publishing::Post.count).to eq(0)
      expect(result.records_for("post").first.detail).to match(/carries no publication date/)
    end

    it "REPORTS an unmapped wp:comment_approved" do
      comment = <<~XML
        <wp:comment>
          <wp:comment_id>1</wp:comment_id>
          <wp:comment_author><![CDATA[Jo]]></wp:comment_author>
          <wp:comment_content><![CDATA[hi]]></wp:comment_content>
          <wp:comment_approved><![CDATA[maybe]]></wp:comment_approved>
          <wp:comment_date_gmt><![CDATA[2026-01-02 03:04:05]]></wp:comment_date_gmt>
        </wp:comment>
      XML
      result = run!(wxr(items: item.sub("</item>", "#{comment}</item>")))

      expect(Publishing::Post.count).to eq(1)
      expect(Discussion::Comment.count).to eq(0)
      expect(result.records_for("comment").first.detail).to match(/unmapped comment_approved value "maybe"/)
    end
  end

  describe "id remapping" do
    it "rebuilds post_parent from the SOURCE ids, in either document order" do
      # The child is written BEFORE its parent — a WXR is emitted in query order and makes
      # no promise about it, which is why the load is two-pass.
      xml = wxr(items: [
        item("wp:post_id" => "20", "wp:post_name" => "child", "title" => "Child",
             "wp:post_type" => "page", "wp:post_parent" => "10"),
        item("wp:post_id" => "10", "wp:post_name" => "parent", "title" => "Parent",
             "wp:post_type" => "page", "wp:post_parent" => "0")
      ].join)
      run!(xml)

      child = Publishing::Page.find_by(slug: "child")
      parent = Publishing::Page.find_by(slug: "parent")
      expect(child.parent).to eq(parent)
      # The SOURCE ids are gone: posts.id is GENERATED ALWAYS AS IDENTITY.
      expect([child.id, parent.id]).not_to include(10, 20)
    end

    it "rebuilds comment_parent the same way, across items" do
      comments = <<~XML
        <wp:comment>
          <wp:comment_id>2</wp:comment_id><wp:comment_parent>1</wp:comment_parent>
          <wp:comment_author><![CDATA[Reply]]></wp:comment_author>
          <wp:comment_content><![CDATA[re]]></wp:comment_content>
          <wp:comment_approved><![CDATA[1]]></wp:comment_approved>
          <wp:comment_date_gmt><![CDATA[2026-01-02 04:00:00]]></wp:comment_date_gmt>
        </wp:comment>
        <wp:comment>
          <wp:comment_id>1</wp:comment_id><wp:comment_parent>0</wp:comment_parent>
          <wp:comment_author><![CDATA[Root]]></wp:comment_author>
          <wp:comment_content><![CDATA[root]]></wp:comment_content>
          <wp:comment_approved><![CDATA[1]]></wp:comment_approved>
          <wp:comment_date_gmt><![CDATA[2026-01-02 03:30:00]]></wp:comment_date_gmt>
        </wp:comment>
      XML
      run!(wxr(items: item.sub("</item>", "#{comments}</item>")))

      root = Discussion::Comment.find_by(author_name: "Root")
      reply = Discussion::Comment.find_by(author_name: "Reply")
      expect(reply.parent).to eq(root)
    end
  end

  describe "custom fields" do
    it "decodes a PHP serialize() payload through the SAME parser the seeding pipeline uses" do
      meta = <<~XML
        <wp:postmeta><wp:meta_key><![CDATA[sizes]]></wp:meta_key>
          <wp:meta_value><![CDATA[a:2:{s:1:"a";i:1;s:1:"b";i:2;}]]></wp:meta_value></wp:postmeta>
      XML
      run!(wxr(items: item.sub("</item>", "#{meta}</item>")))

      row = Publishing::Attribute.find_by(key: "sizes")
      expect(JSON.parse(row.value)).to eq("a" => 1, "b" => 2)
    end

    it "sends a MULTI-VALUED key to the residual bucket, since it cannot satisfy the unique index" do
      # AD-05: (post_id, key) is UNIQUE, so BR-MIGRATE-028's multi-valued meta has to live
      # in the jsonb column — the same split load_post_attributes makes.
      meta = 2.times.map do |i|
        "<wp:postmeta><wp:meta_key><![CDATA[repeated]]></wp:meta_key>" \
          "<wp:meta_value><![CDATA[value-#{i}]]></wp:meta_value></wp:postmeta>"
      end.join
      run!(wxr(items: item.sub("</item>", "#{meta}</item>")))

      post = Publishing::Article.find_by(slug: "an-item")
      expect(Publishing::Attribute.where(key: "repeated")).to be_empty
      expect(post.residual_attributes["repeated"]).to eq(%w[value-0 value-1])
    end

    it "drops the postmeta keys AD-03 already promoted to columns" do
      meta = "<wp:postmeta><wp:meta_key><![CDATA[_edit_lock]]></wp:meta_key>" \
             "<wp:meta_value><![CDATA[1700000000:1]]></wp:meta_value></wp:postmeta>"
      run!(wxr(items: item.sub("</item>", "#{meta}</item>")))

      expect(Publishing::Attribute.where(key: "_edit_lock")).to be_empty
    end
  end

  describe "slug allocation" do
    it "suffixes a slug that collides instead of failing on the partial unique index" do
      Publishing::Article.create!(title: "Existing", slug: "an-item", status: :published,
                                  published_at: 1.day.ago)
      result = run!(wxr(items: item))

      expect(result.records_for("post").first.outcome).to eq(:imported)
      expect(Publishing::Article.pluck(:slug)).to contain_exactly("an-item", "an-item-2")
    end
  end

  describe "authors" do
    it "creates a missing author with authentication disabled" do
      run!(wxr(items: item))

      user = Identity::User.find_by(login: "src_author")
      expect(user.password_digest).to eq(Seeding::Transformations::DISABLED_DIGEST)
      expect(user.role_assignments.pluck(:role)).to eq(["subscriber"]) # `default_role`
      expect(user.email).to eq("src_author@imported.invalid")
    end

    it "reports a mapping that points at a user who no longer exists, and writes no author" do
      result = run!(wxr(items: item),
                    author_mapping: { "src_author" => { "mode" => "existing", "user_id" => "999999" } })

      expect(result.records_for("author").first.outcome).to eq(:failed)
      expect(Publishing::Article.find_by(slug: "an-item").author).to be_nil
    end
  end

  describe "what is not imported" do
    it "reports the attachment it did not fetch, even when asked to fetch" do
      xml = wxr(items: item("wp:post_type" => "attachment",
                            "wp:attachment_url" => "http://source.example/wp-content/uploads/a.png"))
      result = run!(xml, fetch_attachments: true)

      expect(Library::Asset.count).to eq(0)
      record = result.records_for("attachment").first
      expect(record.outcome).to eq(:skipped)
      expect(record.detail).to include("http://source.example/wp-content/uploads/a.png")
      expect(record.detail).to include("makes no outbound requests")
    end

    it "reports a machinery post type by name (AD-02)" do
      result = run!(wxr(items: item("wp:post_type" => "wp_template")))

      expect(result.records_for("other").first.detail).to include("`wp_template` is not a content type")
    end
  end
end
