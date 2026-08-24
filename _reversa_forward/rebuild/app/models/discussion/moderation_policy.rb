# frozen_string_literal: true

module Discussion
  # The moderation pipeline of BR-MIGRATE-065 … 074, in the order the legacy applies it
  # (wp_allow_comment() first, then check_comment(), then the disallowed list).
  # Returns a verdict; the verdict, not the comment, carries the reason
  # (target_domain_model.md § AGG-Comment).
  #
  # Two of the legacy's answers are NOT verdicts — a duplicate (409) and a flood (429)
  # are WP_Error returns from wp_allow_comment(), meaning no comment was created at all.
  # Those raise Comment::Rejected; only the 0/1/'spam'/'trash' answers become verdicts.
  class ModerationPolicy
    Verdict = Struct.new(:outcome, :reason, keyword_init: true)

    # BR-MIGRATE-075 (BR-CMT-11): over-length comment fields return WP_Error with HTTP
    # status 200, not 400. Preserved verbatim — the odd status is the documented
    # behaviour, and wp_check_comment_data_max_lengths()'s codes and messages with it.
    FIELD_LIMITS = {
      author_name:  [245,    "comment_author_column_length",       "<strong>Error:</strong> Your name is too long."],
      author_email: [100,    "comment_author_email_column_length", "<strong>Error:</strong> Your email address is too long."],
      author_url:   [200,    "comment_author_url_column_length",   "<strong>Error:</strong> Your URL is too long."],
      content:      [65_525, "comment_content_column_length",      "<strong>Error:</strong> Your comment is too long."]
    }.freeze
    OVER_LENGTH_STATUS = 200

    # wp_allow_comment(): WP_Error( 'comment_duplicate', …, 409 ). The HTML entity in
    # the message is the legacy's own; functional strings are not copy-edited.
    DUPLICATE_CODE = "comment_duplicate"
    DUPLICATE_MESSAGE = "Duplicate comment detected; it looks as though you&#8217;ve already said that!"
    DUPLICATE_STATUS = 409

    def initialize(comment, actor: nil, settings: Configuration::Setting)
      @comment = comment
      @actor = actor
      @settings = settings
    end

    def call
      # BR-MIGRATE-075 (BR-CMT-11)
      check_field_lengths!

      # BR-MIGRATE-065 (BR-CMT-01): a duplicate — same post, parent, author, email and
      # content, EXCLUDING trashed comments — is rejected with HTTP 409.
      reject!(DUPLICATE_CODE, DUPLICATE_MESSAGE, DUPLICATE_STATUS) if duplicate?

      # BR-MIGRATE-068 (BR-CMT-04) — ⚠️ DEVIATION. See Discussion::RateLimit for what
      # the legacy actually does here and what the recorded rule claims it does.
      # BR-MIGRATE-066 (BR-CMT-02): moderators are never flood-throttled.
      if !privileged? && RateLimit.exceeded?(@comment)
        reject!(RateLimit::CODE, RateLimit::MESSAGE, RateLimit::HTTP_STATUS)
      end

      # BR-MIGRATE-074 (BR-CMT-10): a disallowed-list match overrides ANY approval.
      # ⚠️ DEVIATION: the legacy sets 'trash' if EMPTY_TRASH_DAYS is truthy, otherwise
      # 'spam' — a coupling to bootstrap that no one would predict. The target decouples
      # them: disallowed comments are marked spam, always. Nothing in this class reads
      # a trash-retention setting, which is the whole content of the deviation.
      if matches_any?(setting_list("disallowed_keys"))
        return Verdict.new(outcome: "spam", reason: "disallowed_keys match")
      end

      # BR-MIGRATE-069 (BR-CMT-05): the post author and any user with moderate_comments
      # are auto-approved WITHOUT any moderation check.
      return Verdict.new(outcome: "approved", reason: "author or moderator") if privileged?

      # BR-MIGRATE-070 (BR-CMT-06): comment_moderation = '1' holds every comment and
      # short-circuits all other moderation rules.
      return Verdict.new(outcome: "pending", reason: "comment_moderation holds all") if truthy?("comment_moderation")

      # BR-MIGRATE-071 (BR-CMT-07)
      # `if ( $max_links )` in check_comment(): an unset or zero limit disables the
      # rule entirely. An absent setting reads back as `false` here, hence `.to_s`.
      max_links = @settings["comment_max_links"].to_s.to_i
      if max_links.positive? && @comment.link_count >= max_links
        return Verdict.new(outcome: "pending", reason: "comment_max_links reached")
      end

      # BR-MIGRATE-072 (BR-CMT-08)
      if matches_any?(setting_list("moderation_keys"))
        return Verdict.new(outcome: "pending", reason: "moderation_keys match")
      end

      # BR-MIGRATE-073 (BR-CMT-09): comment_previously_approved = '1' requires a prior
      # approved comment, matched by user_id for registered users, or by author name
      # AND email otherwise.
      if truthy?("comment_previously_approved")
        return Verdict.new(outcome: "pending", reason: "no previously approved comment") unless previously_approved?

        return Verdict.new(outcome: "approved", reason: "author previously approved")
      end

      Verdict.new(outcome: "approved", reason: "passed all moderation rules")
    end

    private

    def reject!(code, message, http_status)
      raise Comment::Rejected.new(code, message, http_status)
    end

    def check_field_lengths!
      FIELD_LIMITS.each do |field, (limit, code, message)|
        next if @comment.public_send(field).to_s.bytesize <= limit

        reject!(code, message, OVER_LENGTH_STATUS)
      end
    end

    def duplicate?
      return false if @comment.post_id.nil?

      Comment.where(post_id: @comment.post_id, parent_id: @comment.parent_id,
                    author_name: @comment.author_name, author_email: @comment.author_email,
                    content: @comment.content)
             .where.not(status: "trashed")
             .exists?
    end

    def privileged?
      return false if @actor.nil?
      return true if @comment.post && @comment.post.author_id == @actor.id

      (@actor.roles & %w[administrator editor]).any?
    end

    def previously_approved?
      scope = Comment.approved
      if @comment.user_id
        scope.where(user_id: @comment.user_id).exists?
      else
        scope.where(author_name: @comment.author_name, author_email: @comment.author_email).exists?
      end
    end

    def truthy?(name)
      value = @settings[name]
      %w[1 true yes].include?(value.to_s) || value == true || value == 1
    end

    def setting_list(name) = @settings[name].to_s.split("\n").map(&:strip).reject(&:empty?)

    # BR-MIGRATE-072 (BR-CMT-08): matched case-insensitively with Unicode against
    # author, email, URL, content, IP and user agent — all six fields.
    #
    # ⚠️ DEVIATION. The legacy builds "#$word#iu" from a preg_quote'd entry and matches
    # it as an UNQUOTED SUBSTRING, so the entry "press" matches "WordPress" — confirmed
    # against the running oracle, wp_check_comment_disallowed_list('…WordPress…')
    # returns true with disallowed_keys = "press". The target matches on WORD
    # BOUNDARIES, so only the standalone word matches.
    def matches_any?(keywords)
      return false if keywords.empty?

      haystack = [@comment.author_name, @comment.author_email, @comment.author_url,
                  @comment.content, @comment.author_ip, @comment.user_agent].compact.join("\n")
      keywords.any? do |word|
        haystack.match?(/(?<![[:word:]])#{Regexp.escape(word)}(?![[:word:]])/i)
      end
    end
  end
end
