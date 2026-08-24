# frozen_string_literal: true

require "rails_helper"
require "nokogiri"

# Shared fixtures for the P-EDIT console request specs. These screens are MODERNIZED
# (target_screens.md § Part 1): there are no golden files and the markup is not compared —
# what is asserted is (1) the single auth gate (auth_redirect → /login), (2) the LITERAL
# strings, verbatim from the cited legacy file:line, and (3) the SAVE RESULT against the
# model row. Authorization is the Access::*Policy objects Wave 3 built.
#
# The oracle corpus has no administrator (only editor/author/subscriber), and user
# management needs one, so this helper seeds its own accounts with known passwords rather
# than reusing seed_oracle_users!.
module ConsoleSpecHelper
  ACCOUNTS = {
    "con_admin"      => { role: "administrator", password: "pw-admin-123" },
    "con_editor"     => { role: "editor",        password: "pw-editor-123" },
    "con_author"     => { role: "author",        password: "pw-author-123" },
    "con_subscriber" => { role: "subscriber",    password: "pw-subscr-123" }
  }.freeze

  def seed_console_accounts!
    ACCOUNTS.each do |login, attrs|
      user = Identity::User.create!(login: login, email: "#{login}@example.com",
                                    nicename: login.tr("_", "-"), display_name: login,
                                    password: attrs[:password])
      user.assign_role(attrs[:role])
    end
  end

  # POST /login establishes the encrypted session cookie; it persists across the request
  # spec's subsequent requests, exactly as a browser's would.
  def login_as(login)
    cookies[Auth::SessionCookie::TEST_COOKIE] = Auth::SessionCookie::TEST_COOKIE_VALUE
    post "/login", params: { log: login, pwd: ACCOUNTS.fetch(login)[:password], testcookie: "1" }
    expect(response).to have_http_status(:see_other)
  end

  def actor(login) = Identity::User.find_by!(login: login)

  def doc = Nokogiri::HTML(response.body)
  def body_text = doc.text

  # A published article to hang comments / revisions off.
  def create_article!(author: actor("con_editor"), title: "A corpus article")
    Publishing::Article.create!(author: author, title: title, status: :published,
                                published_at: Time.current)
  end

  def create_comment!(post: create_article!, **attrs)
    Discussion::Comment.create!({ post: post, author_name: "Jane", author_email: "jane@example.com",
                                  author_url: "https://jane.example", content: "Original body",
                                  status: "pending" }.merge(attrs))
  end

  def category_taxonomy
    Classification::Taxonomy.find_or_create_by!(name: "category") { |t| t.hierarchical = true }
  end

  def create_term!(name: "Jazz", slug: "jazz", **attrs)
    Classification::Term.create!({ taxonomy: category_taxonomy, name: name, slug: slug }.merge(attrs))
  end

  # print_column_headers (class-wp-list-table.php:1188) renders the sort direction as
  # hidden "Sort ascending." text inside the header link, and the check column's caption as
  # a screen-reader span. What these specs assert is the VISIBLE column label, so both are
  # stripped before the comparison, and the (label-less) check column drops out.
  def header_labels(section = "thead")
    doc.css("#{section} th, #{section} td").map do |cell|
      copy = cell.dup
      copy.css(".screen-reader-text, .sorting-indicators").each(&:remove)
      copy.text.strip
    end.reject(&:empty?)
  end

  def create_asset!(**attrs)
    Library::Asset.create!({ slug: "an-image", title: "An image", mime_type: "image/png",
                             byte_size: 1234, alt_text: "old alt", caption: "old caption" }.merge(attrs))
  end
end

RSpec.configure do |config|
  config.include ConsoleSpecHelper, type: :request
end
