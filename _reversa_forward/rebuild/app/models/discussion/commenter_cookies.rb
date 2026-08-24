# frozen_string_literal: true

require "digest/md5"

module Discussion
  # The three commenter cookies — wp_set_comment_cookies(), wp-includes/comment.php:639,
  # the one listener on `set_comment_cookies` (default-filters.php:438).
  #
  # Produces `Set-Cookie` header lines rather than going through the Rails cookie jar,
  # for one byte-level reason: PHP's setcookie() raw-url-encodes the value (`Probe%20One`,
  # `probe.one%40example.com`), while Rack::Utils escapes a space as `+`. The cookie is
  # read back by the comment form's prefill on the next visit, where `+` and `%20` are
  # not the same thing, so the encoding is part of the contract.
  #
  #   COOKIEHASH   md5( siteurl )                    default-constants.php:252
  #   COOKIEPATH   path of home_url() + '/'  ('/')  default-constants.php:297
  #   COOKIE_DOMAIN  false — no `domain=` attribute  default-constants.php:320
  #   lifetime     YEAR_IN_SECONDS (comment_cookie_lifetime, unfiltered) comment.php:664
  #   secure       home_url() is https                                   comment.php:666
  module CommenterCookies
    YEAR_IN_SECONDS = 365 * 24 * 60 * 60

    module_function

    # `comment_author_<hash>`, `comment_author_email_<hash>`, `comment_author_url_<hash>`.
    def names
      %w[comment_author comment_author_email comment_author_url].map { |n| "#{n}_#{cookie_hash}" }
    end

    def cookie_hash
      Digest::MD5.hexdigest(Configuration::Setting["siteurl"].to_s)
    end

    # wp_set_comment_cookies($comment, $user, $cookies_consent):
    #   * a logged-in user gets no cookies at all (comment.php:641);
    #   * consent false REMOVES the three cookies (:645-652) — value ' ', expiry a year
    #     in the past, which PHP emits as `Max-Age=0`;
    #   * consent true sets them for a year (:669-671), the URL esc_url()'d.
    def header_lines(comment, user: nil, consent: true, now: Time.current)
      return [] if user.present?

      if consent == false
        past = now - YEAR_IN_SECONDS
        return names.map { |name| line(name, " ", expires: past, max_age: 0) }
      end

      expires = now + YEAR_IN_SECONDS
      values = [comment.author_name.to_s, comment.author_email.to_s,
                Sanitizing::Formatting.esc_url(comment.author_url.to_s)]
      names.zip(values).map { |name, value| line(name, value, expires: expires, max_age: YEAR_IN_SECONDS) }
    end

    # `name=value; expires=<httpdate>; Max-Age=<n>; path=/[; secure]` — the attribute
    # order PHP's setcookie() writes.
    def line(name, value, expires:, max_age:)
      out = +"#{name}=#{ERB::Util.url_encode(value)}; expires=#{expires.utc.httpdate}; " \
             "Max-Age=#{max_age}; path=#{cookie_path}"
      out << "; secure" if secure?
      out
    end

    def cookie_path
      home = Configuration::Setting["home"].to_s
      "#{home.sub(%r{\Ahttps?://[^/]+}i, "")}/".squeeze("/").then { |p| p.empty? ? "/" : p }
    end

    def secure? = Configuration::Setting["home"].to_s.downcase.start_with?("https://")
  end
end
