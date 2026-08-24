# frozen_string_literal: true

require "net/http"
require "uri"
require "nokogiri"

# Drives the ORACLE's wp-login.php over HTTP, with a cookie jar, and reads back the two
# things the auth screens' contract is made of: the notices (#login_error /
# #login-message, wp-login.php:233-282) and the redirect. Parity::OracleClient only
# GETs; the auth contract is mostly POST.
#
# AD-08: the oracle is the ground truth. Every expectation in spec/requests/auth/ that
# names a legacy string is read from here at spec time, not typed from memory.
module AuthOracle
  BASE = URI.parse(ENV.fetch("ORACLE_URL", "http://127.0.0.1:8099"))
  # tools/install.php and tools/seed.php: the corpus users and their passwords.
  USERS = {
    "oracle_editor" => { password: "pw-editor", email: "oracle_editor@example.com", role: "editor" },
    "oracle_subscriber" => { password: "pw-subscriber", email: "oracle_subscriber@example.com", role: "subscriber" },
    "oracle_author" => { password: "pw-author", email: "oracle_author@example.com", role: "author" }
  }.freeze

  Response = Struct.new(:status, :body, :location, :cookies, keyword_init: true) do
    def doc = @doc ||= Nokogiri::HTML(body.to_s)
    def error_notice = AuthOracle.normalize(doc.at_css("#login_error")&.inner_html)
    def message_notice = AuthOracle.normalize(doc.at_css("#login-message")&.inner_html)
    def title = doc.at_css("title")&.text.to_s
    def field(id) = doc.at_css("##{id}")&.[]("value")
    def aria(id) = doc.at_css("##{id}")&.[]("aria-describedby")
  end

  module_function

  def available?
    Net::HTTP.start(BASE.host, BASE.port, open_timeout: 2, read_timeout: 5) { |h| h.get("/") }
    true
  rescue StandardError
    false
  end

  # Hrefs differ by construction (DEV-006: wp-login.php?action=lostpassword vs
  # /login/lost-password; absolute vs relative); everything else in a notice is
  # compared byte for byte after whitespace collapse.
  def normalize(html)
    return nil if html.nil?

    html.gsub(/href="[^"]*"/, 'href="URL"').gsub(/\s+/, " ").strip
  end

  def request(method, path, form: nil, cookies: {})
    uri = URI.join(BASE, path)
    req = method == :post ? Net::HTTP::Post.new(uri.request_uri) : Net::HTTP::Get.new(uri.request_uri)
    req["User-Agent"] = "reversa-auth-differential/1.0"
    req["Cookie"] = cookies.map { |k, v| "#{k}=#{v}" }.join("; ") unless cookies.empty?
    req.set_form_data(form) if form
    res = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 30) { |http| http.request(req) }
    jar = cookies.dup
    Array(res.get_fields("set-cookie")).each do |line|
      pair = line.split(";", 2).first
      name, value = pair.split("=", 2)
      # An expired cookie (Max-Age=0) is a deletion.
      if line.match?(/Max-Age=0/i)
        jar.delete(name)
      else
        jar[name] = value
      end
    end
    Response.new(status: res.code.to_i, body: res.body.to_s, location: res["location"], cookies: jar)
  end

  # wp-login.php:405 sets the test cookie on the GET; the form echoes it back on POST.
  TEST_COOKIE = { "wordpress_test_cookie" => "WP%20Cookie%20check" }.freeze

  def login(log:, pwd:, rememberme: nil, redirect_to: nil, testcookie: "1", cookies: TEST_COOKIE)
    form = { "log" => log, "pwd" => pwd, "testcookie" => testcookie }
    form["rememberme"] = rememberme if rememberme
    form["redirect_to"] = redirect_to if redirect_to
    request(:post, "/wp-login.php", form: form.compact, cookies: cookies)
  end

  def lost_password(user_login:)
    request(:post, "/wp-login.php?action=lostpassword", form: { "user_login" => user_login })
  end

  def get(path, cookies: {}) = request(:get, path, cookies: cookies)
end
