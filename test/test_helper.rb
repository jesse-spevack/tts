ENV["RAILS_ENV"] ||= "test"
ENV["MAILER_FROM_ADDRESS"] ||= "test@example.com"
ENV["APP_HOST"] ||= "example.com"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "mocktail"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    include Mocktail::DSL

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    def fixture_file_upload(io, mime_type, original_filename:)
      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: io,
        type: mime_type,
        filename: original_filename
      )
      uploaded_file
    end

    def teardown
      Mocktail.reset
    end
  end
end

# Reset Rack::Attack cache between integration tests
class ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.reset! if defined?(Rack::Attack)
  end
end
