require_relative "editor_spec_helper"
RSpec.describe "editor island mount", type: :request do
  before { seed_editor_users!; host! "127.0.0.1" }
  it "renders #gutenberg-root and loads the digested Gutenberg bundle" do
    cookies[Auth::SessionCookie::TEST_COOKIE] = Auth::SessionCookie::TEST_COOKIE_VALUE
    post "/login", params: { log: "editspec_editor", pwd: "pw-editor-1", testcookie: "1" }
    post_rec = Publishing::Article.create!(author: editor_user("editor"), status: :draft, title: "T", content: "<!-- wp:paragraph --><p>x</p><!-- /wp:paragraph -->", excerpt: "")
    get "/console/posts/#{post_rec.id}/edit"
    expect(response.body).to include('id="gutenberg-root"')
    expect(response.body).to match(%r{/assets/gutenberg-[0-9a-f]+\.js})
    expect(response.body).to match(%r{/assets/gutenberg-[0-9a-f]+\.css})
    expect(response.body).to include('id="editor-fallback"')
    puts "MOUNT_OK"
  end
end
