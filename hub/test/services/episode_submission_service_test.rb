# frozen_string_literal: true

require "test_helper"

class EpisodeSubmissionServiceTest < ActiveSupport::TestCase
  include Mocktail::DSL

  setup do
    @podcast = podcasts(:one)
    @user = users(:one)
    @params = {
      title: "Test Episode",
      author: "Test Author",
      description: "Test Description"
    }
    @uploaded_file = StringIO.new("# Test Content\n\nThis is test markdown.")

    Mocktail.replace(UploadAndEnqueueEpisode)
  end

  teardown do
    Mocktail.reset
  end

  test "creates episode with valid params" do
    stubs { |m| UploadAndEnqueueEpisode.call(episode: m.any, content: m.any) }.with { nil }

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: @params,
      uploaded_file: @uploaded_file
    )

    assert result.success?
    assert_kind_of Episode, result.episode
    assert result.episode.persisted?
    assert_equal "Test Episode", result.episode.title
    assert_equal "Test Author", result.episode.author
    assert_equal "Test Description", result.episode.description
  end

  test "returns failure when episode is invalid" do
    invalid_params = { title: "", author: "", description: "" }

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: invalid_params,
      uploaded_file: @uploaded_file
    )

    assert result.failure?
    assert_not result.episode.persisted?
    assert result.episode.errors.any?
  end

  test "calls UploadAndEnqueueEpisode with episode and stripped plain text" do
    stubs { |m| UploadAndEnqueueEpisode.call(episode: m.any, content: m.any) }.with { nil }

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: @params,
      uploaded_file: @uploaded_file
    )

    assert result.success?

    # Verify UploadAndEnqueueEpisode was called with plain text (markdown stripped)
    call = Mocktail.calls(UploadAndEnqueueEpisode, :call).first
    assert_not_nil call
    assert_equal result.episode, call.kwargs[:episode]
    # Should have "Test Content" but NOT the markdown "#" header
    assert_includes call.kwargs[:content], "Test Content"
    refute_includes call.kwargs[:content], "#"
  end

  test "does not call UploadAndEnqueueEpisode when episode save fails" do
    invalid_params = { title: "", author: "", description: "" }

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: invalid_params,
      uploaded_file: @uploaded_file
    )

    assert result.failure?
    assert_empty Mocktail.calls(UploadAndEnqueueEpisode, :call)
  end

  test "returns failure when uploaded file is nil" do
    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: @params,
      uploaded_file: nil
    )

    assert result.failure?
    assert_equal "No file uploaded", result.episode.error_message
    assert_equal "failed", result.episode.status
  end

  test "returns failure when uploaded file is missing read method" do
    fake_file = Object.new

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: @params,
      uploaded_file: fake_file
    )

    assert result.failure?
    assert_match(/file upload/i, result.episode.error_message)
    assert_equal "failed", result.episode.status
  end

  test "rejects file larger than max_characters when limit provided" do
    large_content = "a" * 10_001
    large_file = StringIO.new(large_content)

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: @params,
      uploaded_file: large_file,
      max_characters: 10_000
    )

    assert result.failure?
    assert_not result.episode.persisted?
    assert_includes result.episode.errors[:content].first, "too large"
    assert_includes result.episode.errors[:content].first, "10,001 characters"
    assert_includes result.episode.errors[:content].first, "10,000 characters"
  end

  test "accepts file with exactly max_characters" do
    stubs { |m| UploadAndEnqueueEpisode.call(episode: m.any, content: m.any) }.with { nil }

    content = "a" * 10_000
    file = StringIO.new(content)

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: @params,
      uploaded_file: file,
      max_characters: 10_000
    )

    assert result.success?
    assert result.episode.persisted?
  end

  test "accepts file larger than 10k when max_characters is nil (unlimited)" do
    stubs { |m| UploadAndEnqueueEpisode.call(episode: m.any, content: m.any) }.with { nil }

    large_content = "a" * 50_000
    large_file = StringIO.new(large_content)

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: @params,
      uploaded_file: large_file,
      max_characters: nil
    )

    assert result.success?
    assert result.episode.persisted?
  end

  test "skips character limit check when max_characters not provided" do
    stubs { |m| UploadAndEnqueueEpisode.call(episode: m.any, content: m.any) }.with { nil }

    large_content = "a" * 50_000
    large_file = StringIO.new(large_content)

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: @params,
      uploaded_file: large_file
    )

    assert result.success?
    assert result.episode.persisted?
  end

  test "sets content_preview on episode" do
    stubs { |m| UploadAndEnqueueEpisode.call(episode: m.any, content: m.any) }.with { nil }

    long_content = "A" * 100 + " middle " + "Z" * 100
    uploaded_file = StringIO.new(long_content)

    result = EpisodeSubmissionService.call(
      podcast: @podcast,
      user: @user,
      params: @params,
      uploaded_file: uploaded_file
    )

    assert result.success?
    assert_not_nil result.episode.content_preview
    assert result.episode.content_preview.start_with?("A" * 57)
    assert result.episode.content_preview.include?("... ")
    assert result.episode.content_preview.end_with?("Z" * 57)
  end
end
