# frozen_string_literal: true

module PublicApi
  # /wp/v2/statuses — WP_REST_Post_Statuses_Controller. No permission callback on the
  # route (BR-REST-05), but each STATUS is filtered inside the action
  # (check_read_permission, :294): a status appears only when it is `public` OR the caller
  # can `edit_posts`. `publish` is the only public status, so an anonymous caller sees
  # exactly `{publish}` (verified against the oracle); an editor sees the full set.
  class StatusesController < BaseController
    def index
      body = readable_statuses.transform_values { |s| serialize(s) }
      render_json(body)
    end

    def show
      status = SchemaRegistry::STATUSES[params[:status]]
      unless status && (status[:_public] || can_edit_posts?)
        # rest_cannot_read_status when it exists but is hidden; rest_status_invalid when
        # unknown. Both surface as the same generic invalid for an anonymous caller.
        raise PublicApi::RestError.new("rest_status_invalid", "Invalid status.", 404)
      end
      render_json(serialize(status))
    end

    private

    def readable_statuses
      return SchemaRegistry::STATUSES if can_edit_posts?

      SchemaRegistry::STATUSES.select { |_, s| s[:_public] }
    end

    def can_edit_posts?
      return @can_edit_posts if defined?(@can_edit_posts)

      @can_edit_posts = current_actor ? Access::SitePolicy.new(current_actor, nil).permit?(:edit_posts) : false
    end

    # WP_REST_Post_Statuses_Controller::prepare_item_for_response(), view context. The
    # `archives` link points at the collection of the status's first public post type.
    def serialize(status)
      {
        name: status[:name],
        public: status[:public],
        queryable: status[:queryable],
        slug: status[:slug],
        date_floating: status[:date_floating],
        _links: { archives: [{ href: Url.rest("/wp/v2/posts") }] }
      }
    end
  end
end
