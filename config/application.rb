require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Hub
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

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

    # Email ingest domain for email-to-podcast feature
    # Strip port — email domains never include ports
    # Note: AppConfig::Domain::MAIL_FROM (app/models/app_config.rb) does the same
    # port stripping, but can't be referenced here (loads before autoloading)
    config.x.email_ingest_domain = ENV.fetch("APP_HOST", "localhost").sub(/:\d+\z/, "")
  end
end
