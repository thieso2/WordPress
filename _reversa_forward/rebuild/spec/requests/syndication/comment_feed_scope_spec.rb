# frozen_string_literal: true

require "rails_helper"

# /comments/feed/ — the post-status scope (RISK-023 V3).
#
# class-wp-query.php:2833, the non-archive non-search comment-feed branch, joins the
# comments to their posts and demands `post_status = 'publish'`. Filtering only
# `comment_approved` — which is what this endpoint did — hands anonymous visitors the
# discussion on every draft, pending, scheduled, trashed and private post, and the feed
# prints the post's TITLE and permalink beside each comment.
#
# The seeded corpus carries no comment on a non-public post, so `bin/parity compare` sat
# green at 53/53 through the whole life of the defect. These examples supply the case the
# corpus does not: the leak is latent, not theoretical.
RSpec.describe "Comment feed post-status scope", type: :request do
  let(:author) do
    Identity::User.create!(login: "feed_author", email: "feed_author@example.com",
                           nicename: "feed-author", display_name: "Feed Author",
                           password: "pw-feed-author-1")
  end

  # `scheduled` and `published` both carry a published_at (the posts_published_at_present
  # check constraint); for a scheduled post it is in the future, which is the whole point.
  def article!(status, title)
    at = case status
         when :published then Time.current
         when :scheduled then 1.week.from_now
         end
    Publishing::Article.create!(author: author, title: title, status: status, published_at: at)
  end

  def comment!(post, body)
    Discussion::Comment.create!(post: post, author_name: "Jane", author_email: "jane@example.com",
                                content: body, status: "approved", kind: "comment",
                                submitted_at: Time.current)
  end

  it "carries comments on published posts" do
    comment!(article!(:published, "A public post"), "Visible discussion")

    get "/comments/feed/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visible discussion")
    expect(response.body).to include("A public post")
  end

  # The headline defect: `private` is the status an author chooses precisely so that
  # anonymous visitors cannot read it, and the feed leaked both the comment and the title.
  %i[private draft pending scheduled].each do |status|
    it "withholds comments on #{status} posts from an anonymous visitor" do
      comment!(article!(status, "Secret #{status} title"), "Leaked #{status} discussion")

      get "/comments/feed/"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Leaked #{status} discussion")
      expect(response.body).not_to include("Secret #{status} title")
    end
  end

  it "withholds comments on a trashed post" do
    post = article!(:published, "Since trashed")
    comment!(post, "Discussion on a trashed post")
    post.trash!(actor: author)

    get "/comments/feed/"

    expect(response.body).not_to include("Discussion on a trashed post")
  end

  # The status arm is ADDITIONAL to the approval arm, not a replacement for it.
  it "still withholds an unapproved comment on a published post" do
    post = article!(:published, "A public post")
    Discussion::Comment.create!(post: post, author_name: "Jane", author_email: "jane@example.com",
                                content: "Held for moderation", status: "pending",
                                kind: "comment", submitted_at: Time.current)

    get "/comments/feed/"

    expect(response.body).not_to include("Held for moderation")
  end
end
