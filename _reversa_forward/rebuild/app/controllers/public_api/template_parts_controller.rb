# frozen_string_literal: true

module PublicApi
  # /wp/v2/template-parts — the SAME WP_REST_Templates_Controller, registered a second
  # time for `wp_template_part` (rest-api.php's two `register_rest_route` blocks differ
  # only in `$post_type`). It is a subclass here for exactly that reason: identical
  # behaviour, one constant apart, and inventing a second implementation would be the
  # only way for the two to drift.
  #
  # `lookup` is NOT registered for parts in the legacy — the hierarchy is a template
  # concept — so the action is removed rather than inherited into a route nobody declares.
  class TemplatePartsController < TemplatesController
    KIND = "part"

    undef_method :lookup
  end
end
