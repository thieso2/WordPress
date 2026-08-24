# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

RSpec.describe Platform::Export do
  def user!
    Identity::User.create!(login: "exp_author", email: "exp@example.com",
                           nicename: "exp-author", display_name: "Exp", password: "pw-export-123")
  end

  it "produces a well-formed WXR document with the site channel and each item" do
    author = user!
    article = Publishing::Article.create!(author: author, title: "Hello WXR", slug: "hello-wxr",
                                          content: "<p>Body & more</p>", status: :published,
                                          published_at: Time.current)
    Discussion::Comment.create!(post: article, author_name: "Jo", author_email: "jo@example.com",
                                content: "Nice", status: "approved")

    xml = described_class.wxr(site_url: "http://example.test", site_name: "Example",
                              site_description: "A site")
    doc = Nokogiri::XML(xml)
    expect(doc.errors).to be_empty
    expect(doc.at_xpath("//channel/title").text).to eq("Example")
    expect(doc.at_xpath("//wp:wxr_version", "wp" => "http://wordpress.org/export/1.2/").text).to eq("1.2")

    item = doc.at_xpath("//item")
    expect(item.at_xpath("title").text).to eq("Hello WXR")
    # content:encoded carries the raw body inside CDATA (the ampersand survives).
    expect(item.at_xpath("content:encoded", "content" => "http://purl.org/rss/1.0/modules/content/").text)
      .to include("Body & more")
    # the comment rides along under the item (CDATA text, indent-padded by Builder).
    expect(item.at_xpath("wp:comment/wp:comment_author", "wp" => "http://wordpress.org/export/1.2/").text.strip)
      .to eq("Jo")
  end
end
