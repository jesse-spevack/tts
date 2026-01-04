# frozen_string_literal: true

require "test_helper"

class FeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @podcast = podcasts(:default)
    Mocktail.replace(CloudStorage)
  end

  test "returns XML feed for valid podcast_id" do
    cloud_storage = Mocktail.of(CloudStorage)
    stubs { CloudStorage.new(podcast_id: @podcast.podcast_id) }.with { cloud_storage }
    stubs { cloud_storage.download_file(remote_path: "feed.xml") }.with { "<rss>test feed</rss>" }

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
    cloud_storage = Mocktail.of(CloudStorage)
    stubs { CloudStorage.new(podcast_id: @podcast.podcast_id) }.with { cloud_storage }
    stubs { cloud_storage.download_file(remote_path: "feed.xml") }.with { raise "File not found" }

    get "/feeds/#{@podcast.podcast_id}.xml"

    assert_response :not_found
  end

  test "sets cache headers" do
    cloud_storage = Mocktail.of(CloudStorage)
    stubs { CloudStorage.new(podcast_id: @podcast.podcast_id) }.with { cloud_storage }
    stubs { cloud_storage.download_file(remote_path: "feed.xml") }.with { "<rss></rss>" }

    get "/feeds/#{@podcast.podcast_id}.xml"

    assert_response :success
    assert response.headers["Cache-Control"].include?("max-age=300")
    assert response.headers["Cache-Control"].include?("public")
  end

  teardown do
    Mocktail.reset
  end
end
