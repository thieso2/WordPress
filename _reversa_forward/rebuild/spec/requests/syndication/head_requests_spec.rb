# frozen_string_literal: true

require "rails_helper"

# HEAD on the syndication surfaces. The legacy front controller never branches on the
# request method (wp-blog-header.php -> wp() -> template-loader.php): a HEAD request
# runs the same feed/sitemap/robots code as GET and the web server drops the body, so
# the oracle answers 200 with the GET headers. Rails routes HEAD to the GET action too,
# but ApplicationController#route_identifier keyed the AD-04 declaration lookup on the
# raw request method -- "HEAD syndication/robots#show" can never be declared
# (config/initializers/authorization_declarations.rb registers the routing table's
# verbs, which are GET), so every HEAD raised Access::Declarations::Undeclared (500).
RSpec.describe "Syndication HEAD requests", type: :request do
  {
    "/robots.txt" => "text/plain; charset=utf-8",
    "/wp-sitemap.xml" => "application/xml; charset=UTF-8",
    "/feed/" => "application/rss+xml; charset=UTF-8",
  }.each do |path, content_type|
    it "answers HEAD #{path} like GET: 200, the legacy Content-Type, no body" do
      head path

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to eq(content_type)
      expect(response.body).to be_empty
    end
  end
end
