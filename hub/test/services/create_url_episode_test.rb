# frozen_string_literal: true

require "test_helper"

class CreateUrlEpisodeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
  end

  test "creates episode with processing status" do
    result = nil
    assert_enqueued_with(job: ProcessUrlEpisodeJob) do
      result = CreateUrlEpisode.call(
        podcast: @podcast,
        user: @user,
        url: "https://example.com/article"
      )
    end

    assert result.success?
    assert result.episode.persisted?
    assert_equal "processing", result.episode.status
    assert_equal "url", result.episode.source_type
    assert_equal "https://example.com/article", result.episode.source_url
  end

  test "creates episode with placeholder metadata" do
    result = CreateUrlEpisode.call(
      podcast: @podcast,
      user: @user,
      url: "https://example.com/article"
    )

    assert_equal "Processing...", result.episode.title
    assert_equal "Processing...", result.episode.author
    assert_equal "Processing article from URL...", result.episode.description
  end

  test "fails on invalid URL format" do
    result = CreateUrlEpisode.call(
      podcast: @podcast,
      user: @user,
      url: "not-a-valid-url"
    )

    assert result.failure?
    assert_equal "Invalid URL", result.error
    assert_nil result.episode
  end

  test "fails on empty URL" do
    result = CreateUrlEpisode.call(
      podcast: @podcast,
      user: @user,
      url: ""
    )

    assert result.failure?
    assert_equal "Invalid URL", result.error
  end

  test "enqueues ProcessUrlEpisodeJob" do
    assert_enqueued_with(job: ProcessUrlEpisodeJob) do
      CreateUrlEpisode.call(
        podcast: @podcast,
        user: @user,
        url: "https://example.com/article"
      )
    end
  end
end
