# frozen_string_literal: true

module PublicApi
  # /wp/v2/posts — WP_REST_Posts_Controller for the `post` subtype.
  #
  # ── Reads ────────────────────────────────────────────────────────────────────
  # Collection: no permission callback in `view` context, so it is PUBLIC (BR-REST-05).
  # WHICH posts appear is Retrieval::PostQuery's job — the same object the front-end loop
  # uses — so an untrusted request can never widen the status set past `published`
  # (BR-MIGRATE-041). Item: a permission callback IS registered (`read_item`), so
  # BR-REST-04 governs it — a missing id is rest_post_invalid_id (404); an unreadable
  # status returns false and the server answers 401/403 (BR-REST-06).
  #
  # `context=edit` is a THIRD gate on both, and a different one: it is not about reading
  # the record, it is about reading the record's EDITOR FIELDS (raw markup, password,
  # permalink template), so it demands the edit capability and answers
  # `rest_forbidden_context` — a distinct code from `rest_forbidden`, with a distinct
  # message per endpoint (:166 for the collection, :588 for the item).
  #
  # ── Writes ───────────────────────────────────────────────────────────────────
  # POST /wp/v2/posts, POST|PUT|PATCH /wp/v2/posts/:id, DELETE /wp/v2/posts/:id.
  #
  # ⚠️ Every one of them goes through AGG-Post's OWN COMMANDS — publish!, schedule!,
  # trash!, delete!, or a plain update! — never through raw SQL and never around the
  # model. That is not tidiness: BR-MIGRATE-029/030 (the 60-second scheduling threshold),
  # BR-MIGRATE-032 (slug allocation on first publication), BR-MIGRATE-036 (the status
  # transition row), the revision-on-update rule and the trash column pair are all
  # invariants of the aggregate, already verified against the live oracle by
  # spec/models/publishing/commands_differential_spec.rb. A REST write that assigned
  # `status` directly would silently opt out of all five.
  #
  # The response to every write is prepared in EDIT context (":1109,
  # `$request->set_param( 'context', 'edit' )`"), regardless of what the request asked
  # for — a creator gets the raw fields back.
  class PostsController < BaseController
    include CollectionPagination

    permission :index,   :read_items
    permission :show,    :read_item
    permission :create,  :create_item
    permission :update,  :update_item
    permission :destroy, :delete_item

    REST_BASE = "posts"
    POST_TYPE = "post"

    # The five statuses `wp/v2/posts` accepts on a write, and their AGG-Post spellings.
    # AD-02 keeps the legacy vocabulary internally except for `published`; `future` is
    # the legacy's name for what the model calls `scheduled`, and `trash` is NOT
    # writable through this parameter (the schema's enum omits it — DELETE is the only
    # way in, class-wp-rest-posts-controller.php's `status` enum).
    WRITABLE_STATUSES = {
      "publish" => "published", "future" => "scheduled", "draft" => "draft",
      "pending" => "pending", "private" => "private"
    }.freeze

    def index
      query = Retrieval::PostQuery.new(index_vars, trusted: false)
      total = query.total
      records = query.records.includes(:author).to_a
      set_pagination_headers(total: total, base_path: "/wp/v2/#{self.class::REST_BASE}")
      render_collection(records.map { |p| serialize(p) })
    end

    def show
      render_item(serialize(loaded_post))
    end

    # POST /wp/v2/posts — create_item(). wp_insert_post() through the aggregate: a record
    # is BUILT with the non-status fields, then the requested status is applied by the
    # command that owns it, so the date/status coupling stays where BR-MIGRATE-029/030
    # put it.
    def create
      post = model_scope.new(author: current_actor, title: "", content: "", excerpt: "")
      apply_writable_fields!(post)
      save_with_status!(post)
      response.set_header("Location", Url.rest("/wp/v2/#{self.class::REST_BASE}/#{post.id}"))
      render_item(serialize(post.reload, context: "edit"), status: :created)
    end

    # POST|PUT|PATCH /wp/v2/posts/:id — update_item().
    def update
      post = loaded_post
      apply_writable_fields!(post)
      save_with_status!(post)
      render_item(serialize(post.reload, context: "edit"))
    end

    # DELETE /wp/v2/posts/:id — delete_item(), :1094.
    #
    # Two different operations behind one verb, and the response SHAPES differ, which is
    # how a client tells them apart:
    #   · `?force=true`  -> permanent. `{ "deleted": true, "previous": <the item, edit
    #                       context> }`. Note `previous` carries NO `_links` — it is
    #                       `$previous->get_data()`, the data half of the response only.
    #   · otherwise      -> trash. The trashed record itself, edit context, 200. Trashing
    #                       something already trashed is `rest_already_trashed` / 410, and
    #                       that status is neither 400 nor 404: 410 Gone.
    def destroy
      post = loaded_post
      caps = capabilities_for(post)

      if truthy?(params[:force])
        previous = serialize(post, context: "edit", caps: caps)
        previous.delete(:_links)
        post.delete!(actor: current_actor)
        return render_item({ deleted: true, previous: previous })
      end

      if post.trashed?
        raise PublicApi::RestError.new("rest_already_trashed", "The post has already been deleted.", 410)
      end

      post.trash!(actor: current_actor)
      render_item(serialize(post.reload, context: "edit"))
    end

    private

    def index_vars
      {
        post_type: self.class::POST_TYPE,
        paged: page_param,
        posts_per_page: per_page_param,
        orderby: params[:orderby], order: params[:order],
        s: params[:search]
      }.compact
    end

    def model_scope = Publishing::Article

    # `post` vs `page` for the messages that name the type. Both endpoints say "post" in
    # the legacy's strings (the messages are not per-type), so this is only used where the
    # capability family differs.
    def post_type_object_cap(name)
      self.class::POST_TYPE == "page" ? name.to_s.sub(/_posts\z/, "_pages") : name.to_s
    end

    # ── Permission callbacks ─────────────────────────────────────────────────────

    # get_items_permissions_check(), :160. The collection is public in `view`; `edit`
    # needs the type's edit_posts.
    def read_items
      return true unless context == "edit"
      return true if site_can?(post_type_object_cap("edit_posts"))

      raise forbidden_context("Sorry, you are not allowed to edit posts in this post type.")
    end

    # get_item_permissions_check(), :580: invalid id -> 404; `edit` context without the
    # edit capability -> rest_forbidden_context; an unreadable record -> false (deny).
    def read_item
      post = loaded_post
      if context == "edit" && !policy_for(post).permit?(:edit)
        raise forbidden_context("Sorry, you are not allowed to edit this post.")
      end
      return true if post.status.to_s == "published"

      # A non-published post needs edit rights on it (map_meta_cap read_post -> edit_post
      # for private/draft). Anonymous -> false -> 401.
      policy_for(post).permit?(:edit)
    end

    # create_item_permissions_check(), :714.
    def create_item
      probe = model_scope.new(author: current_actor, status: :draft, title: "", content: "", excerpt: "")
      return true if policy_for(probe).permit?(:edit)

      raise PublicApi::RestError.new("rest_cannot_create",
                                     "Sorry, you are not allowed to create posts as this user.",
                                     current_actor ? 403 : 401)
    end

    # update_item_permissions_check(), :899.
    def update_item
      return true if policy_for(loaded_post).permit?(:edit)

      raise PublicApi::RestError.new("rest_cannot_edit", "Sorry, you are not allowed to edit this post.",
                                     current_actor ? 403 : 401)
    end

    # delete_item_permissions_check(), :1065.
    def delete_item
      return true if policy_for(loaded_post).permit?(:delete)

      raise PublicApi::RestError.new("rest_cannot_delete", "Sorry, you are not allowed to delete this post.",
                                     current_actor ? 403 : 401)
    end

    def forbidden_context(message)
      PublicApi::RestError.new("rest_forbidden_context", message, current_actor ? 403 : 401)
    end

    def loaded_post
      @loaded_post ||= model_scope.find_by(id: params[:id]) ||
                       raise(PublicApi::RestError.new("rest_post_invalid_id", "Invalid post ID.", 404))
    end

    # ── Access, in the ONE layer allowed to touch it (BR-CAP-05) ─────────────────

    def policy_for(post) = Access::PostPolicy.for(current_actor, post)

    def site_can?(capability) = Access::SitePolicy.new(current_actor, nil).permit?(capability.to_sym)

    # get_available_actions()'s six questions plus the two the target hints need,
    # answered here and handed to the serialiser as data.
    def capabilities_for(post)
      policy = policy_for(post)
      PublicApi::PostCapabilities.new(
        edit: policy.permit?(:edit),
        delete: policy.permit?(:delete),
        publish: site_can?(post_type_object_cap("publish_posts")),
        unfiltered_html: site_can?(:unfiltered_html),
        edit_others: site_can?(post_type_object_cap("edit_others_posts")),
        # `$tax->cap->edit_terms` for a hierarchical taxonomy, `assign_terms` for a flat
        # one (:2373); both collapse onto manage_categories / edit_posts at
        # capabilities.php:751-760.
        create_categories: site_can?(:manage_categories),
        assign_categories: site_can?(:assign_categories),
        create_tags: site_can?(:manage_post_tags),
        assign_tags: site_can?(:assign_post_tags)
      )
    end

    def serialize(post, context: self.context, caps: nil)
      PostSerializer.new(post, context: context, caps: caps || capabilities_for(post)).as_json
    end

    # ── The write path ───────────────────────────────────────────────────────────

    # prepare_item_for_database(), minus the status — which is applied by the COMMAND
    # that owns it (`save_with_status!`), not by assignment.
    #
    # Only the fields the request actually carried are touched: a PATCH that sends
    # `{"content": …}` must not blank the title, and `params.key?` is the whole test
    # (WP_REST_Request only copies what was sent).
    def apply_writable_fields!(post)
      post.actor = current_actor
      post.title = params[:title].to_s if params.key?(:title)
      post.content = params[:content].to_s if params.key?(:content)
      post.excerpt = params[:excerpt].to_s if params.key?(:excerpt)
      post.slug = params[:slug].presence if params.key?(:slug)
      post.comment_status = params[:comment_status].to_s if params[:comment_status].present?
      post.template_slug = params[:template].to_s if params.key?(:template)
      post.featured_asset_id = params[:featured_media].presence if params.key?(:featured_media)
      post.author_id = params[:author] if params[:author].present?
      apply_password!(post) if params.key?(:password)
      apply_page_fields!(post) if post.is_a?(Publishing::Page)
      apply_date!(post)
    end

    def apply_page_fields!(post)
      post.parent_id = params[:parent].presence if params.key?(:parent)
      post.menu_order = params[:menu_order].to_i if params.key?(:menu_order)
    end

    # ⚠️ See PostSerializer#base: the column is a BCRYPT DIGEST, so a password can be SET
    # and CLEARED through this endpoint but never read back.
    def apply_password!(post)
      value = params[:password].to_s
      post.password_digest = value.empty? ? nil : BCrypt::Password.create(value)
    end

    # `date` / `date_gmt`. AD-07 keeps only the GMT instant, so both spellings land on the
    # same column; `date_gmt` wins when a request sends both, as it does in the legacy
    # (:1690, post_date_gmt is preferred).
    def apply_date!(post)
      raw = params[:date_gmt].presence || params[:date].presence
      return if raw.blank?

      parsed = Time.zone.parse(raw.to_s)
      post.published_at = parsed if parsed
    rescue ArgumentError
      nil
    end

    # handle_status_param(), :1565, followed by the command that realises the status.
    #
    # The mapping REST status -> command is the point of this method:
    #   publish  -> publish!   (which, per BR-MIGRATE-029/030, may yield `scheduled`
    #                           anyway when the date is 60s+ out — the DATE decides)
    #   future   -> schedule!  (same rule, stated as intent)
    #   anything else -> a plain save with the status assigned.
    # A request with no `status` at all leaves the record's status alone.
    def save_with_status!(post)
      requested = params[:status].presence
      if requested.nil?
        post.save!
        return
      end

      internal = WRITABLE_STATUSES[requested.to_s] ||
                 invalid_enum!("status", WRITABLE_STATUSES.keys)
      check_status_permission!(requested.to_s)

      case internal
      when "published" then post.publish!(actor: current_actor)
      when "scheduled" then post.schedule!(at: post.published_at || Time.current, actor: current_actor)
      else
        post.status = internal
        post.save!
      end
    end

    # :1573-1592, the two `rest_cannot_publish` arms. `private` and `publish`/`future`
    # each require the type's publish_posts, with DIFFERENT messages.
    def check_status_permission!(requested)
      return if %w[draft pending].include?(requested)
      return if site_can?(post_type_object_cap("publish_posts"))

      message = requested == "private" ? "Sorry, you are not allowed to create private posts in this post type." : "Sorry, you are not allowed to publish posts in this post type."
      raise PublicApi::RestError.new("rest_cannot_publish", message, current_actor ? 403 : 401)
    end

    # rest_sanitize_boolean(): "false", "0" and "" are false, everything else truthy.
    def truthy?(value) = !%w[false 0].include?(value.to_s.strip.downcase) && value.to_s.strip.present?
  end
end
