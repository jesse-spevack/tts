# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class FeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @podcast = podcasts(:default)
    @gcs_url = AppConfig::Storage.feed_url(@podcast.podcast_id)
  end

  test "returns XML feed for valid podcast_id" do
    stub_request(:get, @gcs_url)
      .to_return(status: 200, body: "<rss>test feed</rss>", headers: { "Content-Type" => "application/xml" })

    get "/feeds/#{@podcast.podcast_id}.xml"

    assert_response :success
    assert_equal "application/xml; charset=utf-8", response.content_type
    assert_includes response.body, "<rss>test feed</rss>"
  end

  test "returns 404 for nonexistent podcast_id" do
    get "/feeds/podcast_doesnotexist.xml"

    assert_response :not_found
  end

  test "returns 404 when GCS returns error" do
    stub_request(:get, @gcs_url)
      .to_return(status: 404)

    get "/feeds/#{@podcast.podcast_id}.xml"

    assert_response :not_found
  end

  test "sets cache headers" do
    stub_request(:get, @gcs_url)
      .to_return(status: 200, body: "<rss></rss>")

    get "/feeds/#{@podcast.podcast_id}.xml"

    assert_response :success
    assert response.headers["Cache-Control"].include?("max-age=300")
    assert response.headers["Cache-Control"].include?("public")
  end
end
