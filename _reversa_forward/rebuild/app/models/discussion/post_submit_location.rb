# frozen_string_literal: true

module Discussion
  # Where the commenter is sent after a successful submission —
  # wp-comments-post.php:57-80 and the wp_safe_redirect() family it hands the answer to
  # (pluggable.php:1557 wp_sanitize_redirect, :1632 wp_safe_redirect, :1669
  # wp_validate_redirect).
  #
  #   $location = empty( $_POST['redirect_to'] )
  #     ? get_comment_link( $comment )
  #     : $_POST['redirect_to'] . '#comment-' . $comment->comment_ID;
  #   if ( ! $cookies_consent && 'unapproved' === status && email ) add_query_arg( … )
  #   wp_safe_redirect( $location );
  #
  # AD-01: `comment_post_redirect`, `wp_safe_redirect_fallback` and
  # `allowed_redirect_hosts` have no core listeners; their defaults are the behaviour.
  module PostSubmitLocation
    module_function

    # `comment_link` is get_comment_link($comment) (comment-template.php:778), computed by
    # the caller: the permalink lives in Composition, which already depends on Discussion
    # to render comments, so Discussion may not reach back into it (bin/check_cycles).
    # With `page_comments` off — the corpus setting — it is the post permalink plus
    # `#comment-<id>`; the `cpage` branch (get_page_of_comment) is not ported.
    # `request_path` is $_SERVER['REQUEST_URI'] — wp_validate_redirect() resolves a
    # relative `redirect_to` against its directory.
    def call(comment, comment_link:, redirect_to: nil, consent: false, request_path: "/wp-comments-post.php")
      location =
        if php_empty?(redirect_to)
          comment_link
        else
          "#{redirect_to}#comment-#{comment.id}"
        end

      # wp-comments-post.php:60: no consent + unapproved + an email → the two arguments
      # that let the moderation notice show without a cookie.
      if !consent && comment.pending? && comment.author_email.present?
        location = add_query_arg(location, "unapproved" => comment.id.to_s,
                                           "moderation-hash" => ModerationHash.for(comment))
      end

      safe_redirect(location, request_path: request_path)
    end

    # admin_url() — the wp_safe_redirect() fallback (`wp_safe_redirect_fallback`,
    # unfiltered). Verified on the oracle: a `redirect_to` on a foreign host lands on
    # `<siteurl>/wp-admin/`. The path is the legacy's literal; the target's console
    # lives elsewhere (target_screens.md) — reported, not silently re-pointed.
    def fallback_url = "#{Configuration::Setting["siteurl"].to_s.chomp("/")}/wp-admin/"

    # wp_safe_redirect(): sanitize, validate against the home host, else the fallback.
    def safe_redirect(location, request_path:)
      validate_redirect(sanitize_redirect(location), fallback_url, request_path: request_path)
    end

    # wp_sanitize_redirect(), pluggable.php:1557.
    def sanitize_redirect(location)
      s = location.to_s.b.gsub(" ".b, "%20".b)
      s = s.gsub(UTF8_SEQUENCES) { |m| CGI.escape(m) }
      s = s.gsub(%r{[^a-z0-9\-~+_.?#=&;,/:%!*\[\]()@]}in, "".b)
      s = Sanitizing::Kses.wp_kses_no_null(s)
      s = Sanitizing::Formatting._deep_replace(%w[%0d %0a %0D %0A], s)
      Sanitizing::Bytes.utf8(s)
    end

    # The multi-byte UTF-8 run wp_sanitize_redirect() urlencode()s, 1..40 sequences at
    # a time (the legacy regex, transcribed).
    UTF8_SEQUENCES = /(?:[\xC2-\xDF][\x80-\xBF]|\xE0[\xA0-\xBF][\x80-\xBF]|[\xE1-\xEC][\x80-\xBF]{2}|\xED[\x80-\x9F][\x80-\xBF]|[\xEE-\xEF][\x80-\xBF]{2}|\xF0[\x90-\xBF][\x80-\xBF]{2}|[\xF1-\xF3][\x80-\xBF]{3}|\xF4[\x80-\x8F][\x80-\xBF]{2}){1,40}/n

    # wp_validate_redirect(), pluggable.php:1669.
    def validate_redirect(location, fallback, request_path:)
      location = sanitize_redirect(location.to_s.b.gsub(/\A[ \t\n\r\0\x08\x0B]+|[ \t\n\r\0\x08\x0B]+\z/n, "".b))
      location = "http:#{location}" if location.start_with?("//")

      cut = location.index("?")
      test = cut ? location[0, cut] : location
      parsed = parse_url(test)
      return fallback if parsed.nil?

      scheme = parsed[:scheme]
      return fallback if scheme && !%w[http https].include?(scheme)

      host = parsed[:host]
      path = parsed[:path].to_s
      # `! empty( $test['path'] )` — PHP's empty() is also true for the string "0".
      if host.nil? && !path.empty? && path != "0" && path[0] != "/"
        dir = File.dirname(URI.parse("http://placeholder#{request_path}").path.to_s + "?") rescue ""
        dir = "" if dir == "."
        location = "/#{"#{dir}/".sub(%r{\A/+}, "")}#{location}"
      end

      return fallback if host.nil? && (scheme || parsed[:user] || parsed[:pass] || parsed[:port])

      %i[user pass host].each do |component|
        return fallback if parsed[component] && parsed[component].match?(%r{[:/?#@]})
      end

      home_host = parse_url(Configuration::Setting["home"].to_s)&.dig(:host).to_s
      return fallback if host && host != home_host && home_host.downcase != host

      location
    end

    # parse_url() for the pieces wp_validate_redirect() reads. The `sanitizing` pack's
    # php_parse_url() covers the authority; the path is what follows it.
    def parse_url(url)
      parsed = Sanitizing::Formatting.php_parse_url(url.to_s.b)
      return nil if parsed.nil?

      rest = url.to_s
      rest = rest.sub(/\A[a-zA-Z][a-zA-Z0-9+.\-]*:/, "") if parsed[:scheme]
      rest = rest.sub(%r{\A//[^/?#]*}, "") if rest.start_with?("//")
      parsed.merge(path: rest.split("#", 2).first.to_s)
    end

    # add_query_arg(), functions.php:1144, for a hash of scalar arguments over a URL that
    # may carry a query and a fragment.
    def add_query_arg(uri, args)
      frag = uri[/#.*\z/m].to_s
      uri = uri.delete_suffix(frag)

      protocol = ""
      if uri =~ %r{\Ahttp://}i
        protocol = "http://"
        uri = uri[7..]
      elsif uri =~ %r{\Ahttps://}i
        protocol = "https://"
        uri = uri[8..]
      end

      if uri.include?("?")
        base, query = uri.split("?", 2)
        base += "?"
      elsif !protocol.empty? || !uri.include?("=")
        base = "#{uri}?"
        query = ""
      else
        base = ""
        query = uri
      end

      qs = Rack::Utils.parse_nested_query(query).transform_values { |v| v.is_a?(String) ? v : v.to_s }
      args.each { |k, v| v == false ? qs.delete(k.to_s) : qs[k.to_s] = v.to_s }

      # urlencode_deep() encodes the VALUES only (functions.php:1159) and build_query()
      # encodes nothing (`_http_build_query(…, false)`), so keys go out raw; PHP's
      # urlencode() also encodes `~`, which CGI.escape leaves alone.
      ret = qs.map { |k, v| "#{k}=#{CGI.escape(v).gsub("~", "%7E")}" }.join("&")
      ret = ret.gsub(/\A\?+|\?+\z/, "")
      ret = ret.gsub(/=(&|\z)/, '\1')
      ret = "#{protocol}#{base}#{ret}#{frag}"
      ret = ret.sub(/\?+\z/, "")
      ret.gsub("?#", "#")
    end

    # PHP empty(): '', '0', null.
    def php_empty?(value) = value.nil? || value == "" || value == "0"
  end
end
