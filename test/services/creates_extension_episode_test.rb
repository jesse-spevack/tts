# frozen_string_literal: true

require "test_helper"

class CreatesExtensionEpisodeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
    @long_content = "This is test content. " * 10
    @valid_params = {
      podcast: @podcast,
      user: @user,
      title: "Test Title",
      content: @long_content,
      url: "https://example.com/article",
      author: "Test Author",
      description: "Test description"
    }
  end

  test "creates episode with extension source type" do
    result = CreatesExtensionEpisode.call(**@valid_params)

    assert result.success?
    assert_equal :extension, result.data.source_type.to_sym
  end

  test "stores all metadata correctly" do
    result = CreatesExtensionEpisode.call(**@valid_params)

    assert result.success?
    assert_equal "Test Title", result.data.title
    assert_equal "Test Author", result.data.author
    assert_equal "Test description", result.data.description
    assert_equal "https://example.com/article", result.data.source_url
    assert_equal @long_content, result.data.source_text
  end

  test "sets episode status to processing" do
    result = CreatesExtensionEpisode.call(**@valid_params)

    assert_equal "processing", result.data.status
  end

  test "enqueues ProcessesFileEpisodeJob" do
    assert_enqueued_with(job: ProcessesFileEpisodeJob) do
      CreatesExtensionEpisode.call(**@valid_params)
    end
  end

  test "returns failure when content is blank" do
    result = CreatesExtensionEpisode.call(**@valid_params.merge(content: ""))

    assert result.failure?
    assert_equal "Content cannot be empty", result.error
  end

  test "returns failure when content is under 100 characters" do
    result = CreatesExtensionEpisode.call(**@valid_params.merge(content: "short"))

    assert result.failure?
    assert_equal "Content must be at least 100 characters", result.error
  end

  test "returns failure when url is blank" do
    result = CreatesExtensionEpisode.call(**@valid_params.merge(url: ""))

    assert result.failure?
    assert_includes result.error, "Source url"
  end

  test "returns failure when url is invalid" do
    result = CreatesExtensionEpisode.call(**@valid_params.merge(url: "not-a-url"))

    assert result.failure?
    assert_includes result.error, "Source url"
  end

  test "returns failure when content exceeds max characters" do
    @user.update!(account_type: :standard)
    max_chars = @user.character_limit
    long_content = "a" * (max_chars + 1)

    result = CreatesExtensionEpisode.call(**@valid_params.merge(content: long_content))

    assert result.failure?
    assert_includes result.error, "exceeds your plan's"
  end

  test "sets content preview" do
    result = CreatesExtensionEpisode.call(**@valid_params)

    assert result.data.content_preview.present?
  end

  test "assigns episode to correct user and podcast" do
    result = CreatesExtensionEpisode.call(**@valid_params)

    assert_equal @user, result.data.user
    assert_equal @podcast, result.data.podcast
  end
end
