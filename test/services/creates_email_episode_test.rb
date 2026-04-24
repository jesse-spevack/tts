# frozen_string_literal: true

require "test_helper"

class CreatesEmailEpisodeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @podcast = @user.primary_podcast
    @valid_text = "A" * 150 # Above 100 char minimum
  end

  test "creates episode with processing status" do
    result = nil
    assert_enqueued_with(job: ProcessesEmailEpisodeJob) do
      result = CreatesEmailEpisode.call(
        podcast: @podcast,
        user: @user,
        text: @valid_text
      )
    end

    assert result.success?
    assert result.data.persisted?
    assert_equal "pending", result.data.status
    assert_equal "email", result.data.source_type
    assert_equal @valid_text, result.data.source_text
  end

  test "creates episode with placeholder metadata" do
    result = CreatesEmailEpisode.call(
      podcast: @podcast,
      user: @user,
      text: @valid_text
    )

    assert_equal "Processing...", result.data.title
    assert_equal "Processing...", result.data.author
    assert_equal "Processing email content...", result.data.description
  end

  test "uses user primary_podcast" do
    result = CreatesEmailEpisode.call(
      podcast: @podcast,
      user: @user,
      text: @valid_text
    )

    assert_equal @user.primary_podcast, result.data.podcast
  end

  test "fails on empty text" do
    result = CreatesEmailEpisode.call(
      podcast: @podcast,
      user: @user,
      text: ""
    )

    assert result.failure?
    assert_equal "Content cannot be empty", result.error
    assert_nil result.data
  end

  test "fails on nil text" do
    result = CreatesEmailEpisode.call(
      podcast: @podcast,
      user: @user,
      text: nil
    )

    assert result.failure?
    assert_equal "Content cannot be empty", result.error
  end

  test "fails on text under 100 characters" do
    result = CreatesEmailEpisode.call(
      podcast: @podcast,
      user: @user,
      text: "A" * 99
    )

    assert result.failure?
    assert_equal "Content must be at least 100 characters", result.error
  end

  test "succeeds on text exactly 100 characters" do
    result = CreatesEmailEpisode.call(
      podcast: @podcast,
      user: @user,
      text: "A" * 100
    )

    assert result.success?
  end

  test "enqueues ProcessesEmailEpisodeJob" do
    assert_enqueued_with(job: ProcessesEmailEpisodeJob) do
      CreatesEmailEpisode.call(
        podcast: @podcast,
        user: @user,
        text: @valid_text
      )
    end
  end

  test "fails when text exceeds max characters for user tier" do
    free_user = users(:free_user)
    max_chars = free_user.character_limit
    text_over_limit = "A" * (max_chars + 1)

    result = CreatesEmailEpisode.call(
      podcast: free_user.primary_podcast,
      user: free_user,
      text: text_over_limit
    )

    assert result.failure?
    assert_includes result.error, "exceeds your plan's"
  end

  test "succeeds for unlimited tier user with very long text" do
    unlimited_user = users(:unlimited_user)
    very_long_text = "A" * 100_000

    result = CreatesEmailEpisode.call(
      podcast: unlimited_user.primary_podcast,
      user: unlimited_user,
      text: very_long_text
    )

    assert result.success?
  end

  test "enqueues with priority 0 for premium user" do
    premium_user = users(:complimentary_user)

    assert_enqueued_with(job: ProcessesEmailEpisodeJob, priority: 0) do
      CreatesEmailEpisode.call(podcast: premium_user.primary_podcast, user: premium_user, text: @valid_text)
    end
  end

  test "enqueues with priority 10 for free user" do
    free_user = users(:free_user)

    assert_enqueued_with(job: ProcessesEmailEpisodeJob, priority: 10) do
      CreatesEmailEpisode.call(podcast: free_user.primary_podcast, user: free_user, text: @valid_text)
    end
  end
end
