# frozen_string_literal: true

require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "redirects legacy domain to current host with 301" do
    get "/episodes", headers: { "HOST" => "tts.verynormal.dev" }

    assert_response :moved_permanently
    assert_equal "https://example.com/episodes", response.location
  end

  test "redirects legacy domain preserving query string" do
    get "/episodes?page=2&sort=recent", headers: { "HOST" => "tts.verynormal.dev" }

    assert_response :moved_permanently
    assert_equal "https://example.com/episodes?page=2&sort=recent", response.location
  end

  test "does not redirect requests to current domain" do
    get root_url

    assert_response :success
  end

  test "does not redirect webhook paths on legacy domain" do
    post "/webhooks/stripe", headers: { "HOST" => "tts.verynormal.dev" }

    assert_response :bad_request  # Stripe signature check fails, but no redirect
  end

  test "does not redirect internal API paths on legacy domain" do
    patch "/api/internal/episodes/1", headers: { "HOST" => "tts.verynormal.dev" }

    assert_response :unauthorized
  end
end
