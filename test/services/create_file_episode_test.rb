# frozen_string_literal: true

require "test_helper"

class CreateFileEpisodeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @podcast = podcasts(:one)
  end

  test "creates episode with markdown source type" do
    result = CreateFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test Title",
      author: "Test Author",
      description: "Test description",
      content: "# Markdown content"
    )

    assert result.success?
    assert_equal :file, result.episode.source_type.to_sym
    assert_equal "Test Title", result.episode.title
    assert_equal "Test Author", result.episode.author
    assert_equal "Test description", result.episode.description
    assert_equal "# Markdown content", result.episode.source_text
  end

  test "sets episode status to processing" do
    result = CreateFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: "Content here"
    )

    assert_equal "processing", result.episode.status
  end

  test "enqueues ProcessFileEpisodeJob" do
    assert_enqueued_with(job: ProcessFileEpisodeJob) do
      CreateFileEpisode.call(
        podcast: @podcast,
        user: @user,
        title: "Test",
        author: "Author",
        description: "Desc",
        content: "Content here"
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

  test "returns failure when content exceeds max characters" do
    @user.update!(tier: :free)
    max_chars = CalculatesMaxCharactersForUser.call(user: @user)
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
    assert_includes result.error, "too long"
  end

  test "sets content preview" do
    result = CreateFileEpisode.call(
      podcast: @podcast,
      user: @user,
      title: "Test",
      author: "Author",
      description: "Desc",
      content: "# Header\n\nSome markdown content here."
    )

    assert result.episode.content_preview.present?
  end
end
