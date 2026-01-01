# frozen_string_literal: true

require "test_helper"

class CreateFileEpisodeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
  end

  test "creates episode with markdown source type" do
    long_content = "# Markdown content\n\n" + ("This is test content. " * 10)

    result = CreateFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test Title",
      author: "Test Author",
      description: "Test description",
      content: long_content
    )

    assert result.success?
    assert_equal :file, result.data.source_type.to_sym
    assert_equal "Test Title", result.data.title
    assert_equal "Test Author", result.data.author
    assert_equal "Test description", result.data.description
    assert_equal long_content, result.data.source_text
  end

  test "sets episode status to processing" do
    long_content = "A" * 150

    result = CreateFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: long_content
    )

    assert_equal "processing", result.data.status
  end

  test "enqueues ProcessFileEpisodeJob" do
    long_content = "A" * 150

    assert_enqueued_with(job: ProcessFileEpisodeJob) do
      CreateFileEpisode.call(
        podcast: @podcast,
        user: @user,
        title: "Test",
        author: "Author",
        description: "Desc",
        content: long_content
      )
    end
  end

  test "returns failure when content is blank" do
    result = CreateFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: ""
    )

    assert result.failure?
    assert_equal "Content cannot be empty", result.error
  end

  test "returns failure when content is under 100 characters" do
    result = CreateFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: "short"
    )

    assert result.failure?
    assert_equal "Content must be at least 100 characters", result.error
  end

  test "returns failure when content exceeds max characters" do
    @user.update!(account_type: :standard)
    max_chars = AppConfig::Tiers.character_limit_for(@user.tier)
    long_content = "a" * (max_chars + 1)

    result = CreateFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: long_content
    )

    assert result.failure?
    assert_includes result.error, "exceeds your plan's"
  end

  test "sets content preview" do
    long_content = "# Header\n\n" + ("Some markdown content here. " * 10)

    result = CreateFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: long_content
    )

    assert result.data.content_preview.present?
  end
end
