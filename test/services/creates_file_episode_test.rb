# frozen_string_literal: true

require "test_helper"

class CreatesFileEpisodeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
  end

  test "creates episode with markdown source type" do
    long_content = "# Markdown content\n\n" + ("This is test content. " * 10)

    result = CreatesFileEpisode.call(
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

    result = CreatesFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: long_content
    )

    assert_equal "processing", result.data.status
  end

  test "enqueues ProcessesFileEpisodeJob" do
    long_content = "A" * 150

    assert_enqueued_with(job: ProcessesFileEpisodeJob) do
      CreatesFileEpisode.call(
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
    result = CreatesFileEpisode.call(
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
    result = CreatesFileEpisode.call(
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
    max_chars = @user.character_limit
    long_content = "a" * (max_chars + 1)

    result = CreatesFileEpisode.call(
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

    result = CreatesFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: long_content
    )

    assert result.data.content_preview.present?
  end

  test "enqueues with priority 0 for premium user" do
    premium_user = users(:subscriber)

    assert_enqueued_with(job: ProcessesFileEpisodeJob, priority: 0) do
      CreatesFileEpisode.call(
        podcast: @podcast, user: premium_user,
        title: "Test", author: "Author", description: "Desc", content: "A" * 150
      )
    end
  end

  test "enqueues with priority 10 for free user" do
    free_user = users(:free_user)

    assert_enqueued_with(job: ProcessesFileEpisodeJob, priority: 10) do
      CreatesFileEpisode.call(
        podcast: @podcast, user: free_user,
        title: "Test", author: "Author", description: "Desc", content: "A" * 150
      )
    end
  end
end
