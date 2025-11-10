ENV["RAILS_ENV"] ||= "test"
ENV["MAILER_FROM_ADDRESS"] ||= "test@example.com"
ENV["MAILER_HOST"] ||= "example.com"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Skip auto-creating podcast for fixture users
    setup do
      User.skip_callback(:create, :after, :create_default_podcast)
    end

    teardown do
      User.set_callback(:create, :after, :create_default_podcast)
    end

    # Add more helper methods to be used by all tests here...
  end
end
