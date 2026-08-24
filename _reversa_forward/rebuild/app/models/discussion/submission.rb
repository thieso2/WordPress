# frozen_string_literal: true

module Discussion
  # A comment submitted over HTTP — wp_handle_comment_submission()
  # (wp-includes/comment.php:3936) and the pre-insert half of wp_new_comment()
  # (comment.php:2372), as one object. The moderation pipeline itself is NOT here: it is
  # Discussion::ModerationPolicy, reached through Comment.moderate, and this class only
  # gets a submission into the shape that pipeline takes.
  #
  # Every refusal is a Comment::Rejected carrying the legacy's own error code, message
  # and HTTP status. Two families of refusal exist in the legacy and both are preserved:
  #   * a WP_Error WITH data — wp-comments-post.php:27-36 renders wp_die() with that
  #     status (403 closed, 403 reply-to-unapproved, 200 for every validation message,
  #     409 duplicate, 429 flood, 500 save error);
  #   * a WP_Error WITHOUT data — wp-comments-post.php:38 `exit`s with an empty 200 body
  #     (post not found, trashed, draft for a reader who may not see it, password
  #     protected). Those carry `http_status: nil` and an empty message here.
  #
  # AD-01: the nine actions this path fires (comment_id_not_found, comment_closed,
  # comment_on_trash, comment_on_draft, comment_on_password_protected,
  # pre_comment_on_post, comment_reply_to_unapproved_comment, comment_post,
  # set_comment_cookies) have no listeners in core that change the outcome; they are
  # gone and the outcome is what is written here. The one that RECORDS state
  # (`comment_post` → moderation) is already a ModerationVerdict row.
  #
  # Access is deliberately NOT referenced: whether the actor may read a private or
  # unpublished post is answered by the caller through `can_read_post`, so the
  # Access → Discussion edge stays one-way (target_architecture.md Note 2).
  class Submission
    # The legacy field names — the form's own (comment-template.php:2532) and the
    # hidden id fields (:2046). `wp-comment-cookies-consent` and `redirect_to` are read by
    # wp-comments-post.php, not by the handler, and are the controller's business.
    FIELDS = %w[comment author email url comment_post_ID comment_parent
                _wp_unfiltered_html_comment].freeze

    # Messages verbatim — comment.php:3982, 4013, 4063, 4107, 4110, 4132, 4151.
    MSG_REPLY_TO_UNAPPROVED = "Sorry, replies to unapproved comments are not allowed."
    MSG_CLOSED              = "Sorry, comments are closed for this item."
    MSG_NOT_ALLOWED         = "Sorry, comments are not allowed for this item."
    MSG_NOT_LOGGED_IN       = "Sorry, you must be logged in to comment."
    MSG_REQUIRE_NAME_EMAIL  = "<strong>Error:</strong> Please fill the required fields."
    MSG_REQUIRE_VALID_EMAIL = "<strong>Error:</strong> Please enter a valid email address."
    MSG_REQUIRE_COMMENT     = "<strong>Error:</strong> Please type your comment text."
    MSG_SAVE_ERROR          = "<strong>Error:</strong> The comment could not be saved. Please try again later."

    # wp_new_comment(), comment.php:2427: `substr( $commentdata['comment_agent'], 0, 254 )`.
    AGENT_MAX_BYTES = 254

    attr_reader :fields, :actor

    # `fields`   — a Hash of the raw request fields, string keys, string values (anything
    #              that is not a String is treated the way `is_string()` treats it: unset).
    # `actor`    — the authenticated Identity::User, or nil.
    # `html_filter` — :restricted or :none; see FieldFilters.content. The controller
    #              decides it, because deciding it needs Access and the nonce.
    # `can_read_post` — current_user_can('read_post', $id) for the given post.
    def initialize(fields:, remote_ip:, user_agent:, actor: nil, html_filter: :restricted,
                   can_read_post: ->(_post) { false }, settings: Configuration::Setting)
      @fields = fields
      @remote_ip = remote_ip.to_s
      @user_agent = user_agent.to_s
      @actor = actor
      @html_filter = html_filter
      @can_read_post = can_read_post
      @settings = settings
    end

    # Returns the saved Discussion::Comment, or raises Comment::Rejected.
    def call
      post_id = php_int(fields["comment_post_ID"])
      author  = string?("author") ? FieldFilters.php_trim(Sanitizing::Formatting.strip_tags(fields["author"].b)) : ""
      email   = string?("email") ? FieldFilters.php_trim(fields["email"]) : ""
      url     = string?("url") ? FieldFilters.php_trim(fields["url"]) : ""
      content = string?("comment") ? FieldFilters.php_trim(fields["comment"]) : ""
      author, email, url, content = [author, email, url, content].map { |s| FieldFilters.utf8(s) }
      parent_id = 0

      # comment.php:3961-3983: a reply may only go under an APPROVED comment. `0 ===
      # (int) $comment_approved` is true for '0', 'spam' and 'trash' alike, so any
      # non-approved parent — or a parent that does not exist — is refused with 403.
      if fields.key?("comment_parent")
        parent_id = php_int(fields["comment_parent"]).abs
        if parent_id != 0
          parent = Comment.find_by(id: parent_id)
          refuse!("comment_reply_to_unapproved_comment", MSG_REPLY_TO_UNAPPROVED, 403) if parent.nil? || !parent.approved?
        end
      end

      post = Publishing::Post.find_by(id: post_id)
      # comment.php:3987: `empty( $post->comment_status )`. AD-02: attachments are
      # Library::Asset rows, not posts, so a comment on an attachment — which the legacy
      # accepts when the attachment's own comment_status is open — is "not found" here.
      refuse!("comment_id_not_found") if post.nil?

      # comment.php:4002: a private post the actor may not read is indistinguishable
      # from a missing one.
      refuse!("comment_id_not_found") if post.private? && !@can_read_post.call(post)

      # comment.php:4010 — comments_open() is tested BEFORE the trash/draft states, so a
      # trashed post with comments closed answers 403, not silence.
      refuse!("comment_closed", MSG_CLOSED, 403) unless post.comment_status.to_s == "open"
      refuse!("comment_on_trash") if post.trashed?
      # comment.php:4036: `! $status_obj->public && ! $status_obj->private` — only
      # 'publish' is public and only 'private' is private; every other status (draft,
      # pending, future, auto-draft) lands here, and what the submitter sees depends on
      # whether they could read the post.
      unless post.published? || post.private?
        refuse!("comment_on_draft", MSG_NOT_ALLOWED, 403) if @can_read_post.call(post)
        refuse!("comment_on_draft")
      end
      # comment.php:4053: post_password_required(). No `wp-postpass_*` cookie is read on
      # this path (the read surface does not set one either), so a password on the post
      # is the whole test.
      refuse!("comment_on_password_protected") if post.password_digest.present?

      user_id = nil
      if actor
        # comment.php:4073-4081: a logged-in submitter's identity fields come from the
        # user record, whatever the form said.
        author  = actor.display_name.presence || actor.login
        email   = actor.email.to_s
        url     = actor.url.to_s
        user_id = actor.id
      elsif truthy?("comment_registration")
        refuse!("not_logged_in", MSG_NOT_LOGGED_IN, 403)
      end

      # comment.php:4104-4113. `require_name_email` only binds anonymous submitters.
      if truthy?("require_name_email") && actor.nil?
        refuse!("require_name_email", MSG_REQUIRE_NAME_EMAIL, 200) if email.empty? || author.empty?
        refuse!("require_valid_email", MSG_REQUIRE_VALID_EMAIL, 200) unless FieldFilters.is_email?(email)
      end

      # comment.php:4131: the `allow_empty_comment` filter defaults to false.
      refuse!("require_valid_comment", MSG_REQUIRE_COMMENT, 200) if content.empty?

      # BR-MIGRATE-075 (BR-CMT-11): wp_check_comment_data_max_lengths() runs on the
      # values as submitted, BEFORE the save filters (comment.php:4136). ModerationPolicy
      # checks the filtered values again; the first check is the one the legacy answers
      # with, so it is made first.
      check_field_lengths!(author_name: author, author_email: email, author_url: url, content: content)

      # wp_new_comment(), comment.php:2390-2427: IP and agent from the request,
      # the IP reduced to `[0-9a-fA-F:., ]`, the agent cut at 254 bytes.
      ip = @remote_ip.gsub(/[^0-9a-fA-F:., ]/, "")
      agent = @user_agent.byteslice(0, AGENT_MAX_BYTES).to_s.scrub("")

      # wp_filter_comment(), comment.php:2251 — the pre_comment_* pipelines.
      attributes = {
        post: post, parent_id: parent_id.zero? ? nil : parent_id, user_id: user_id,
        author_name: FieldFilters.author_name(author),
        author_email: FieldFilters.author_email(email).presence,
        author_url: FieldFilters.author_url(url).presence,
        author_ip: ip.presence, user_agent: agent.presence,
        content: FieldFilters.content(content, html_filter: @html_filter),
        kind: "comment", submitted_at: Time.current
      }

      # wp_allow_comment() + wp_check_comment_data() + wp_insert_comment(): the pipeline
      # that already exists. A duplicate (409), a flood (429) or an over-length filtered
      # field (200) raises Comment::Rejected from inside it.
      Comment.moderate(attributes, actor: actor, settings: @settings)
    rescue ActiveRecord::RecordInvalid
      # The target's own invariants (thread depth, parent on the same post) have no
      # legacy counterpart — wp_insert_comment() takes any parent id. A refused insert
      # is reported the way the legacy reports its own failed insert (comment.php:4151).
      refuse!("comment_save_error", MSG_SAVE_ERROR, 500)
    end

    private

    def refuse!(code, message = "", http_status = nil)
      raise Comment::Rejected.new(code, message, http_status)
    end

    def string?(name) = fields[name].is_a?(String)

    def truthy?(name)
      value = @settings[name]
      !(value.nil? || value == false || value == 0 || value == "" || value == "0")
    end

    # wp_check_comment_data_max_lengths(), comment.php:1319 — the same limits, codes and
    # messages ModerationPolicy carries; byte lengths (`mb_strlen(…, '8bit')`/strlen).
    def check_field_lengths!(values)
      ModerationPolicy::FIELD_LIMITS.each do |field, (limit, code, message)|
        next if values.fetch(field).to_s.bytesize <= limit

        refuse!(code, message, ModerationPolicy::OVER_LENGTH_STATUS)
      end
    end

    # PHP's (int) cast of a request value: leading whitespace, an optional sign, digits,
    # and a numeric string in exponent form is converted through float. Anything else
    # is 0; a non-string (an array-shaped parameter) is 1 when non-empty, as PHP casts
    # arrays.
    def php_int(value)
      case value
      when String
        m = value.match(/\A[ \t\n\r\v\f]*([+-]?\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)/)
        return 0 if m.nil?

        m[1].match?(/[.eE]/) ? m[1].to_f.to_i : m[1].to_i
      when nil then 0
      else value.respond_to?(:empty?) && value.empty? ? 0 : 1
      end
    end
  end
end
