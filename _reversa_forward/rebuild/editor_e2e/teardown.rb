# Removes the editor e2e fixtures so the corpus returns to exactly its seeded state — the
# 25-screen parity gate compares against the oracle, and a leftover published fixture post
# would show up in archives.
if (post = Publishing::Article.find_by(slug: "island-e2e-fixture"))
  post.destroy!
end
if (user = Identity::User.find_by(login: "island_e2e"))
  user.role_assignments.destroy_all if user.respond_to?(:role_assignments)
  user.destroy!
end
puts "e2e fixtures removed"
