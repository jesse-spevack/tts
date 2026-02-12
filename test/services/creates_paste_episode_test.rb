# frozen_string_literal: true

require "test_helper"

class CreatesPasteEpisodeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @valid_text = "A" * 150 # Above 100 char minimum
  end

  test "creates episode with processing status" do
    result = nil
    assert_enqueued_with(job: ProcessesPasteEpisodeJob) do
      result = CreatesPasteEpisode.call(
        podcast: @podcast,
        user: @user,
        text: @valid_text
      )
    end

    assert result.success?
    assert result.data.persisted?
    assert_equal "processing", result.data.status
    assert_equal "paste", result.data.source_type
    assert_equal @valid_text, result.data.source_text
  end

  test "creates episode with placeholder metadata when no title or author provided" do
    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: @valid_text
    )

    assert_equal "Processing...", result.data.title
    assert_equal "Processing...", result.data.author
    assert_equal "Processing pasted text...", result.data.description
  end

  test "creates episode with user-provided title when given" do
    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: @valid_text,
      title: "My Custom Title"
    )

    assert_equal "My Custom Title", result.data.title
    assert_equal "Processing...", result.data.author
  end

  test "creates episode with user-provided author when given" do
    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: @valid_text,
      author: "Jane Doe"
    )

    assert_equal "Processing...", result.data.title
    assert_equal "Jane Doe", result.data.author
  end

  test "creates episode with both user-provided title and author" do
    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: @valid_text,
      title: "My Title",
      author: "Jane Doe"
    )

    assert_equal "My Title", result.data.title
    assert_equal "Jane Doe", result.data.author
  end

  test "treats blank title as not provided" do
    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: @valid_text,
      title: "  ",
      author: ""
    )

    assert_equal "Processing...", result.data.title
    assert_equal "Processing...", result.data.author
  end

  test "fails on empty text" do
    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: ""
    )

    assert result.failure?
    assert_equal "Content cannot be empty", result.error
    assert_nil result.data
  end

  test "fails on nil text" do
    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: nil
    )

    assert result.failure?
    assert_equal "Content cannot be empty", result.error
  end

  test "fails on text under 100 characters" do
    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: "A" * 99
    )

    assert result.failure?
    assert_equal "Content must be at least 100 characters", result.error
  end

  test "succeeds on text exactly 100 characters" do
    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: "A" * 100
    )

    assert result.success?
  end

  test "enqueues ProcessesPasteEpisodeJob" do
    assert_enqueued_with(job: ProcessesPasteEpisodeJob) do
      CreatesPasteEpisode.call(
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

    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: free_user,
      text: text_over_limit
    )

    assert result.failure?
    assert_includes result.error, "exceeds your plan's"
  end

  test "succeeds when text is at max characters for user tier" do
    free_user = users(:free_user)
    max_chars = free_user.character_limit
    text_at_limit = "A" * max_chars

    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: free_user,
      text: text_at_limit
    )

    assert result.success?
  end

  test "succeeds for unlimited tier user with very long text" do
    unlimited_user = users(:unlimited_user)
    very_long_text = "A" * 100_000

    result = CreatesPasteEpisode.call(
      podcast: @podcast,
      user: unlimited_user,
      text: very_long_text
    )

    assert result.success?
  end

  test "enqueues with priority 0 for premium user" do
    premium_user = users(:subscriber)

    assert_enqueued_with(job: ProcessesPasteEpisodeJob, priority: 0) do
      CreatesPasteEpisode.call(podcast: @podcast, user: premium_user, text: @valid_text)
    end
  end

  test "enqueues with priority 10 for free user" do
    free_user = users(:free_user)

    assert_enqueued_with(job: ProcessesPasteEpisodeJob, priority: 10) do
      CreatesPasteEpisode.call(podcast: @podcast, user: free_user, text: @valid_text)
    end
  end
end
