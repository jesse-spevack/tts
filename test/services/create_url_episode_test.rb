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
    assert result.data.persisted?
    assert_equal "processing", result.data.status
    assert_equal "url", result.data.source_type
    assert_equal "https://example.com/article", result.data.source_url
  end

  test "creates episode with placeholder metadata" do
    result = CreateUrlEpisode.call(
      podcast: @podcast,
      user: @user,
      url: "https://example.com/article"
    )

    assert_equal "Processing...", result.data.title
    assert_equal "Processing...", result.data.author
    assert_equal "Processing article from URL...", result.data.description
  end

  test "fails on invalid URL format" do
    result = CreateUrlEpisode.call(
      podcast: @podcast,
      user: @user,
      url: "not-a-valid-url"
    )

    assert result.failure?
    assert_equal "Invalid URL", result.error
    assert_nil result.data
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

  test "returns failure when episode validation fails" do
    # Pass nil user to trigger validation failure
    result = CreateUrlEpisode.call(
      podcast: @podcast,
      user: nil,
      url: "https://example.com/article"
    )

    assert result.failure?
    assert_includes result.error, "User"
  end

  test "does not enqueue job when validation fails" do
    assert_no_enqueued_jobs do
      CreateUrlEpisode.call(
        podcast: @podcast,
        user: nil,
        url: "https://example.com/article"
      )
    end
  end

  test "fails on substack inbox URL" do
    result = CreateUrlEpisode.call(
      podcast: @podcast,
      user: @user,
      url: "https://substack.com/inbox/post/182789127"
    )

    assert result.failure?
    assert_match(/inbox links require login/, result.error)
  end

  test "does not enqueue job for substack inbox URL" do
    assert_no_enqueued_jobs do
      CreateUrlEpisode.call(
        podcast: @podcast,
        user: @user,
        url: "https://substack.com/inbox/post/182789127"
      )
    end
  end

  test "normalizes substack URL before storing" do
    result = CreateUrlEpisode.call(
      podcast: @podcast,
      user: @user,
      url: "https://open.substack.com/pub/author/p/title?utm_campaign=post"
    )

    assert result.success?
    assert_equal "https://author.substack.com/p/title", result.data.source_url
  end

  test "fails on twitter.com URL with helpful message" do
    result = CreateUrlEpisode.call(
      podcast: @podcast,
      user: @user,
      url: "https://twitter.com/user/status/123456789"
    )

    assert result.failure?
    assert_match(/Twitter\/X links aren't supported/, result.error)
  end

  test "fails on x.com URL with helpful message" do
    result = CreateUrlEpisode.call(
      podcast: @podcast,
      user: @user,
      url: "https://x.com/user/status/123456789"
    )

    assert result.failure?
    assert_match(/Twitter\/X links aren't supported/, result.error)
  end

  test "does not enqueue job for twitter URL" do
    assert_no_enqueued_jobs do
      CreateUrlEpisode.call(
        podcast: @podcast,
        user: @user,
        url: "https://x.com/user/status/123456789"
      )
    end
  end
end
