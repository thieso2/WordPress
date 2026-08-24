# frozen_string_literal: true

module Access
  # Legacy post_type = 'page' carries its own capability family: `capability_type =>
  # 'page'` in create_initial_post_types() (wp-includes/post.php), so
  # get_post_type_capabilities() yields edit_pages, edit_others_pages, publish_pages,
  # read_private_pages, ... The arms are the same (capabilities.php:81-423); only the
  # names differ, and `read` / `manage_options` have no family form.
  class PagePolicy < PostPolicy
    private

    def cap(name) = name.to_s.sub(/_posts\z/, "_pages")
  end
end
