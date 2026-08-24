# frozen_string_literal: true

module PublicApi
  # A `WP_Error` as the REST server serialises it (class-wp-rest-server.php:1435,
  # rest_convert_error_to_response). The envelope is `{code, message, data:{status}}`,
  # and the HTTP status is `data.status`. Raised anywhere below the controller and
  # rendered by PublicApi::BaseController#render_rest_error.
  #
  # BR-MIGRATE-236 (BR-REST-03) / BR-MIGRATE-239 (BR-REST-06): the status is part of the
  # error, not a controller decision — a denial is 401 or 403 depending on who asked, and
  # that choice is made where the error is built (`deny!`), so the shape is uniform.
  class RestError < StandardError
    attr_reader :code, :status, :additional_data

    def initialize(code, message, status, additional_data = {})
      @code = code
      @status = status
      @additional_data = additional_data
      super(message)
    end

    def as_json
      { code: code, message: message, data: { status: status }.merge(additional_data) }
    end
  end
end
