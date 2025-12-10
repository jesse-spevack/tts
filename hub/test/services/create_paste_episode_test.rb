# frozen_string_literal: true

require "test_helper"

class CreatePasteEpisodeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @valid_text = "A" * 150 # Above 100 char minimum
  end

  test "creates episode with processing status" do
    result = nil
    assert_enqueued_with(job: ProcessPasteEpisodeJob) do
      result = CreatePasteEpisode.call(
        podcast: @podcast,
        user: @user,
        text: @valid_text
      )
    end

    assert result.success?
    assert result.episode.persisted?
    assert_equal "processing", result.episode.status
    assert_equal "paste", result.episode.source_type
    assert_equal @valid_text, result.episode.source_text
  end

  test "creates episode with placeholder metadata" do
    result = CreatePasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: @valid_text
    )

    assert_equal "Processing...", result.episode.title
    assert_equal "Processing...", result.episode.author
    assert_equal "Processing pasted text...", result.episode.description
  end

  test "fails on empty text" do
    result = CreatePasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: ""
    )

    assert result.failure?
    assert_equal "Text cannot be empty", result.error
    assert_nil result.episode
  end

  test "fails on nil text" do
    result = CreatePasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: nil
    )

    assert result.failure?
    assert_equal "Text cannot be empty", result.error
  end

  test "fails on text under 100 characters" do
    result = CreatePasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: "A" * 99
    )

    assert result.failure?
    assert_equal "Text must be at least 100 characters", result.error
  end

  test "succeeds on text exactly 100 characters" do
    result = CreatePasteEpisode.call(
      podcast: @podcast,
      user: @user,
      text: "A" * 100
    )

    assert result.success?
  end

  test "enqueues ProcessPasteEpisodeJob" do
    assert_enqueued_with(job: ProcessPasteEpisodeJob) do
      CreatePasteEpisode.call(
        podcast: @podcast,
        user: @user,
        text: @valid_text
      )
    end
  end
end
