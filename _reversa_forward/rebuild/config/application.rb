require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Rebuild
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Enums, citext, partial and GIN indexes are not expressible in schema.rb.
    config.active_record.schema_format = :sql

    # topology_decision.md option 3: the three leaf packs are the ONLY CI-enforced
    # boundaries. Each declares zero dependencies and is held there by bin/check_cycles.
    config.autoload_paths += Dir[root.join("packs", "*", "app")]
    config.eager_load_paths += Dir[root.join("packs", "*", "app")]

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")


    # AD-04: the only way to a stored file is the declared `/wp-content/uploads/*` route
    # (and the static file server in front of it). Active Storage's own redirect/proxy
    # routes would be undeclared public surface, so they are not drawn.
    config.active_storage.draw_routes = false

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
