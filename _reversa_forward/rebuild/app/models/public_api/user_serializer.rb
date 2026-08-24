# frozen_string_literal: true

module PublicApi
  # WP_REST_Users_Controller::prepare_item_for_response(), the `view` context
  # (class-wp-rest-users-controller.php:1100). The edit-context fields (email, roles,
  # capabilities, registered_date) are omitted — an anonymous caller only ever sees view.
  class UserSerializer
    include Entity

    def initialize(user)
      @user = user
    end

    def self.collection(users) = users.map { |u| new(u).as_json }

    def as_json
      {
        id: user.id,
        name: user.display_name.to_s,
        url: user.url.to_s,
        description: "", # AD-03: no `description` user-meta column; the oracle's is empty.
        link: Entity.links.author_posts_url(author_link_user),
        slug: user.nicename.to_s,
        avatar_urls: Avatar.urls(user.email),
        meta: [],
        _links: {
          self: [{ href: Url.rest("/wp/v2/users/#{user.id}"), targetHints: { allow: %w[GET] } }],
          collection: [{ href: Url.rest("/wp/v2/users") }]
        }
      }
    end

    private

    attr_reader :user

    # Links.author_posts_url reads `user.nicename`; author_link_user is the same record.
    def author_link_user
      user
    end
  end
end
