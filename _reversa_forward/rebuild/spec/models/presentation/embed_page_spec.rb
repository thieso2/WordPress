# frozen_string_literal: true

require "rails_helper"
require_relative "../../parity/harness/normalizer"

# Presentation::EmbedPage against the oracle's own capture.
#
# DIFFERENTIAL in the sense the golden manifest defines: golden-web-embed.html IS the
# oracle's rendered /2026/03/hello-world/embed/ (screen_modernization_decision.md keeps
# web.embed literal), so the expectation is the file, not a paraphrase of
# theme-compat/embed.php. The same Parity::Normalizer the harness uses is applied to the
# rebuild's output — same rules, same justification (normalizer.rb's header).
RSpec.describe Presentation::EmbedPage do
  EMBED_GOLDEN = Rails.root.join("spec/parity/golden/golden-web-embed.html")
  EMBED_SITE = "http://127.0.0.1:3100"

  before do
    Configuration::Setting.find_or_initialize_by(name: "home").update!(value: EMBED_SITE)
    Configuration::Setting.find_or_initialize_by(name: "blogname")
                          .update!(value: "Reversa Oracle &quot;7.2&quot; 😀")
    # ⚠️ id: 1 on purpose. `print_embed_sharing_dialog()` builds its ids from
    # `get_the_ID() . '-' . wp_rand()` (embed.php:1204) and the normalizer masks only the
    # wp_rand() half — the post id is part of the literal screen, and the oracle's
    # hello-world is post 1.
    insert_post!(
      "id" => 1, "type" => "Publishing::Article", "author_id" => author.id,
      "title" => "Hello world!", "slug" => "hello-world",
      "content" => "<!-- wp:paragraph -->\n<p>Welcome to WordPress. This is your first post." \
                   " Edit or delete it, then start writing!</p>\n<!-- /wp:paragraph -->",
      "excerpt" => "", "status" => "published", "published_at" => Time.utc(2026, 3, 15, 9, 59),
      "comment_status" => "open", "comment_count" => 1, "menu_order" => 0,
      "guid" => SecureRandom.uuid
    )
    post = Publishing::Article.find(1)
    taxonomy = Classification::Taxonomy.find_or_create_by!(name: "category") { |t| t.hierarchical = true }
    term = Classification::Term.create!(taxonomy_id: taxonomy.id, name: "Uncategorized",
                                        slug: "uncategorized", description: "")
    Classification::Assignment.create!(term_id: term.id, classifiable_type: "Publishing::Post",
                                       classifiable_id: post.id, position: 0)
  end

  def author
    @author ||= Identity::User.create!(login: "oracle_admin", nicename: "oracle_admin",
                                       display_name: "oracle_admin", email: "oracle_admin@example.test",
                                       password_digest: "x", registered_at: Time.current)
  end

  # posts.id is GENERATED ALWAYS (AD-05), so pinning the oracle's id takes
  # OVERRIDING SYSTEM VALUE — same helper shape as screen_resolution_spec.rb:222.
  def insert_post!(attributes)
    conn = ActiveRecord::Base.connection
    columns = attributes.keys
    conn.execute(<<~SQL)
      INSERT INTO posts (#{columns.map { |c| conn.quote_column_name(c) }.join(", ")})
        OVERRIDING SYSTEM VALUE
        VALUES (#{columns.map { |c| conn.quote(attributes[c]) }.join(", ")})
    SQL
  end

  it "renders the oracle's embed document, byte for byte after normalization" do
    post = Publishing::Article.find_by!(slug: "hello-world")
    html = described_class.new(post: post, site_url: EMBED_SITE,
                               theme_slug: "twentytwentyfive").to_html
    normalized = Parity::Normalizer.new.call(html, content_type: "text/html")
    expect(normalized.lines.map(&:chomp)).to eq(File.read(EMBED_GOLDEN).lines.map(&:chomp))
  end
end
