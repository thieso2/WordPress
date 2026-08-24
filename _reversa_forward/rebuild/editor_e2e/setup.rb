# Provisions the editor e2e fixtures (run via: bin/rails runner editor_e2e/setup.rb).
# Idempotent, and safe to re-run after `oracle:seed` wipes the corpus — which it does,
# so the e2e must own its fixtures rather than borrowing corpus rows.
#
# The fixture post is a DRAFT: it never appears on a front-end archive, so it cannot
# perturb the 25-screen parity gate. The site-editor test restores the templates and
# Global Styles it touches (see site_editor.mjs).
user = Identity::User.find_or_initialize_by(login: "island_e2e")
user.assign_attributes(email: "island_e2e@example.com", nicename: "island-e2e",
                       display_name: "Island E2E", password: "island-pw-1")
user.save!
user.assign_role("administrator")

post = Publishing::Article.find_by(slug: "island-e2e-fixture") ||
       Publishing::Article.new(slug: "island-e2e-fixture")
post.assign_attributes(author: user, status: :draft, title: "E2E seed title",
                       content: "<!-- wp:paragraph --><p>Original body</p><!-- /wp:paragraph -->",
                       excerpt: "")
post.save!
puts "POST_ID=#{post.id}"
