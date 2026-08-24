# frozen_string_literal: true

module Identity
  # The shape of WP_Error as the authentication surface uses it (wp-includes/
  # class-wp-error.php): an ORDERED list of (code, message) pairs, where a code may carry
  # several messages and a message may carry a severity. wp-login.php reads all three
  # facts back -- `get_error_code()` is the FIRST code added (login_header() decides
  # whether to shake the form on it, wp-login.php:59), `get_error_data($code)` is the
  # severity ('message' renders as an info notice rather than an error, :241), and every
  # message of every code is printed (:244).
  #
  # The messages are the legacy's LITERAL strings, HTML included (`<strong>Error:</strong>`
  # and the "Lost your password?" link are part of the string the legacy prints), so a
  # message here is HTML the view prints raw. Anything user-supplied that reaches one is
  # escaped by the caller with the same esc_html() the legacy applies -- see
  # Identity::User.authenticate_login.
  class Errors
    Entry = Struct.new(:code, :message, :severity, keyword_init: true)

    include Enumerable

    def initialize
      @entries = []
    end

    # WP_Error::add(). `severity: :message` is the legacy's `$data = 'message'`.
    def add(code, message, severity: :error)
      @entries << Entry.new(code: code.to_s, message: message, severity: severity)
      self
    end

    def each(&) = @entries.each(&)

    def any? = @entries.any?
    def empty? = @entries.empty?
    def size = @entries.size

    # WP_Error::get_error_codes(): unique, in first-seen order.
    def codes = @entries.map(&:code).uniq

    # WP_Error::get_error_code(): the first code, or nil.
    def code = @entries.first&.code

    def messages_for(code) = @entries.select { |e| e.code == code.to_s }.map(&:message)

    def messages = @entries.map(&:message)

    def severity_of(code) = @entries.find { |e| e.code == code.to_s }&.severity

    # wp-login.php:233-251 splits the printed output in two: messages carrying the
    # 'message' severity go into #login-message (info), everything else into
    # #login_error (error).
    def error_messages = @entries.reject { |e| e.severity == :message }.map(&:message)
    def info_messages = @entries.select { |e| e.severity == :message }.map(&:message)

    # wp-login.php:1493: the first code's severity decides the input's aria-describedby.
    def first_is_message? = @entries.first&.severity == :message
  end
end
