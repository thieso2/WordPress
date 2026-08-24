# frozen_string_literal: true

module PublicApi
  # The REST URL space. `rest_url()` (wp-includes/rest-api.php:471) is
  # `home_url( '/wp-json' . $path )` under the default (pretty-permalink) rewrite, which
  # is this corpus's. Absolute, because every `_links` href and every `link` field the
  # oracle emits is absolute and the parity normaliser maps host+port to <SITE>.
  module Url
    module_function

    def home = Configuration::Setting["home"].to_s.chomp("/")
    def rest_root = "#{home}/wp-json"
    def rest(path) = "#{rest_root}#{path}"
  end
end
