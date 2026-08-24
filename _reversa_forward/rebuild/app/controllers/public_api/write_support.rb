# frozen_string_literal: true

module PublicApi
  # The pieces every /wp-json WRITE endpoint shares, transcribed from the REST server
  # rather than invented:
  #
  #   * a 201 carries `Location` (class-wp-rest-server.php:1112, rest_ensure_response)
  #   * every response carries `Allow` — rest_send_allow_header(), :465 — listing the
  #     methods on the MATCHED ROUTE whose permission callback passes FOR THIS CALLER.
  #     That same list is what `_links.self[0].targetHints.allow` carries, so both are
  #     computed once, by the controller, and handed to the serialiser (BR-CAP-05: the
  #     controller is the only layer that touches Access).
  #   * a missing required argument is `rest_missing_callback_param`, raised before the
  #     callback runs (class-wp-rest-request.php:930)
  #   * `force` is a boolean argument parsed by rest_sanitize_boolean() (:2247)
  #
  # AD-04 still applies to every action these helpers serve: the write routes are
  # declared in config/initializers/authorization_declarations.rb, and the per-record
  # capability arms run INSIDE the action, answering with the legacy's WP_Error envelope.
  module WriteSupport
    extend ActiveSupport::Concern

    # rest_send_allow_header() writes the header on EVERY response, read or write.
    def set_allow_header(methods)
      response.set_header("Allow", Array(methods).join(", "))
    end

    # class-wp-rest-server.php:1112 — a created resource answers 201 with the item's URL.
    def render_created(payload, location:)
      response.set_header("Location", location)
      render_json(payload, status: :created)
    end

    # WP_REST_Request::has_valid_params(), class-wp-rest-request.php:930:
    #   WP_Error( 'rest_missing_callback_param',
    #             sprintf( __( 'Missing parameter(s): %s' ), implode( ', ', $required ) ),
    #             array( 'status' => 400, 'params' => $required ) )
    def require_params!(*names)
      missing = names.map(&:to_s).reject { |name| params[name].to_s.present? }
      return if missing.empty?

      raise PublicApi::RestError.new("rest_missing_callback_param",
                                     "Missing parameter(s): #{missing.join(", ")}",
                                     400, { params: missing })
    end

    # rest_sanitize_boolean(): '', '0', 'false' and 0 are false, everything else true.
    def force_param?
      value = params[:force]
      return false if value.nil?

      !%w[0 false].include?(value.to_s.downcase) && value.to_s.present?
    end

    # A capability refusal. BR-MIGRATE-239 (BR-REST-06) / rest_authorization_required_code():
    # 401 before an identity exists, 403 after.
    def rest_denied(code, message)
      PublicApi::RestError.new(code, message, current_actor ? 403 : 401)
    end

    # A `{raw: "..."}` object or a bare string — both are accepted for every
    # rendered/raw field pair (WP_REST_Posts_Controller::prepare_item_for_database,
    # class-wp-rest-posts-controller.php:1180 `is_string( $request['title'] ) ? … : $request['title']['raw']`).
    def raw_text(value)
      case value
      when Hash then value["raw"] || value[:raw]
      when ActionController::Parameters then value[:raw]
      else value
      end.to_s
    end

    # `param.present?` is wrong for a write: `""` and `0` are meaningful values. This is
    # `isset( $request['x'] )` — the key was sent at all.
    def sent?(name) = params.key?(name.to_s)
  end
end
