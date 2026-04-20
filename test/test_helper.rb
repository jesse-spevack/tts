ENV["RAILS_ENV"] ||= "test"
ENV["MAILER_FROM_ADDRESS"] ||= "test@example.com"
ENV["APP_HOST"] ||= "example.com"

# Test-mode Stripe price IDs for the three credit packs (agent-team-qc7t).
# These are real test-mode Price objects created in Stripe 2026-04-19.
# AppConfig::Credits::PACKS reads these at class-load time via ENV.fetch, so
# they must be set BEFORE requiring the Rails environment below.
ENV["STRIPE_PRICE_ID_CREDIT_PACK_5"] ||= "price_1TO99OD8ZGZanIYEXCH3vTYw"
ENV["STRIPE_PRICE_ID_CREDIT_PACK_10"] ||= "price_1TO9A5D8ZGZanIYE56zeSE89"
ENV["STRIPE_PRICE_ID_CREDIT_PACK_20"] ||= "price_1TO9AMD8ZGZanIYEYnsWPXYg"

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "mocktail"

WebMock::Config.instance.query_values_notation = :flat
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
      WebMock.reset!
    end
  end
end

# Reset Rack::Attack cache between integration tests
class ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.reset! if defined?(Rack::Attack)
  end
end
