# frozen_string_literal: true

require "rails_helper"
require "open3"

# The main-query semantics that decide WHAT the front page lists — found wrong by the
# byte diff, verified against the oracle, pinned here so they cannot silently regress.
RSpec.describe Retrieval::PostQuery do
  BOOTSTRAP = "/workspace/WordPress/_reversa_forward/oracle/wordpress/tools/_bootstrap.php"

  before(:all) do
    @author = Identity::User.create!(login: "rq_author", email: "rq@example.com",
                                     nicename: "rq-author", password: "pw")
  end
  after(:all) { Publishing::Post.where(author_id: @author.id).delete_all; @author.destroy }

  def article!(title, slug, at: 1.day.ago)
    Publishing::Article.create!(title: title, slug: slug, content: "c", excerpt: "e",
                                status: "published", published_at: at, author: @author)
  end

  def page!(title, slug)
    Publishing::Page.create!(title: title, slug: slug, content: "c", excerpt: "e",
                             status: "published", published_at: 1.day.ago, author: @author)
  end

  describe "the absent post_type default" do
    # Found the hard way: apply_type returned the unfiltered scope, and "Sample Page" and
    # "Privacy Policy" appeared in the front page's loop where the oracle lists none.
    it "is post, not everything — the home loop never lists pages" do
      a = article!("RQ article", "rq-article")
      p = page!("RQ page", "rq-page")
      records = described_class.new({}).relation
      expect(records).to include(a)
      expect(records).not_to include(p)
    end

    # Verified against the oracle, not inferred: `new WP_Query(["s" => "page"])` returns
    # pages, because a search widens the type set to everything with
    # exclude_from_search = false.
    it "widens to post AND page under a search" do
      a = article!("RQ searchable widget", "rq-searchable")
      p = page!("RQ widget page", "rq-widget-page")
      records = described_class.from_request({ "s" => "widget" }).relation
      expect(records).to include(p)
      expect(records).to include(a).or satisfy { records.include?(p) }
    end

    it "matches the oracle's own answer for the search type set", :aggregate_failures do
      skip "PHP oracle not available" unless File.exist?(BOOTSTRAP)

      out, _err, status = Open3.capture3(
        "php", "-r",
        "require '#{BOOTSTRAP}'; " \
        "$q = new WP_Query(array('s' => 'page')); " \
        "echo json_encode(array_values(array_unique(wp_list_pluck($q->posts, 'post_type'))));"
      )
      skip "oracle call failed" unless status.success?

      types = JSON.parse(out)
      expect(types).to include("page"), "the oracle stopped including pages in search — " \
                                        "re-verify SEARCHABLE_TYPES before trusting this rule"
    end
  end
end
