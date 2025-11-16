require "test_helper"
require "minitest/mock"

class EpisodeSubmissionServiceTest < ActiveSupport::TestCase
  setup do
    @podcast = podcasts(:one)
    @params = {
      title: "Test Episode",
      author: "Test Author",
      description: "Test Description"
    }
    @uploaded_file = StringIO.new("# Test Content\n\nThis is test markdown.")

    @mock_uploader = Object.new
    @mock_enqueuer = Object.new
  end

  test "creates episode with valid params" do
    @mock_uploader.define_singleton_method(:upload_staging_file) { |content:, filename:| "staging/#{filename}" }
    @mock_enqueuer.define_singleton_method(:enqueue_episode_processing) { |**args| nil }

    result = EpisodeSubmissionService.new(
      podcast: @podcast,
      params: @params,
      uploaded_file: @uploaded_file,
      gcs_uploader: @mock_uploader,
      enqueuer: @mock_enqueuer
    ).call

    assert result.success?
    assert_kind_of Episode, result.episode
    assert result.episode.persisted?
    assert_equal "Test Episode", result.episode.title
    assert_equal "Test Author", result.episode.author
    assert_equal "Test Description", result.episode.description
  end

  test "returns failure when episode is invalid" do
    invalid_params = { title: "", author: "", description: "" }

    result = EpisodeSubmissionService.new(
      podcast: @podcast,
      params: invalid_params,
      uploaded_file: @uploaded_file,
      gcs_uploader: @mock_uploader,
      enqueuer: @mock_enqueuer
    ).call

    assert result.failure?
    assert_not result.episode.persisted?
    assert result.episode.errors.any?
  end

  test "uploads file to GCS staging with correct content and filename" do
    uploaded_content = nil
    uploaded_filename = nil

    @mock_uploader.define_singleton_method(:upload_staging_file) do |content:, filename:|
      uploaded_content = content
      uploaded_filename = filename
      "staging/#{filename}"
    end
    @mock_enqueuer.define_singleton_method(:enqueue_episode_processing) { |**args| nil }

    result = EpisodeSubmissionService.new(
      podcast: @podcast,
      params: @params,
      uploaded_file: @uploaded_file,
      gcs_uploader: @mock_uploader,
      enqueuer: @mock_enqueuer
    ).call

    assert result.success?
    assert_includes uploaded_content, "Test Content"
    assert_match(/^\d+-\d+\.md$/, uploaded_filename)
    assert uploaded_filename.start_with?("#{result.episode.id}-")
  end

  test "enqueues processing with correct parameters" do
    enqueued_args = nil
    podcast_id = @podcast.podcast_id

    @mock_uploader.define_singleton_method(:upload_staging_file) do |content:, filename:|
      "podcasts/#{podcast_id}/staging/#{filename}"
    end
    @mock_enqueuer.define_singleton_method(:enqueue_episode_processing) do |**args|
      enqueued_args = args
      nil
    end

    result = EpisodeSubmissionService.new(
      podcast: @podcast,
      params: @params,
      uploaded_file: @uploaded_file,
      gcs_uploader: @mock_uploader,
      enqueuer: @mock_enqueuer
    ).call

    assert result.success?
    assert_equal result.episode.id, enqueued_args[:episode_id]
    assert_equal @podcast.podcast_id, enqueued_args[:podcast_id]
    assert_kind_of String, enqueued_args[:staging_path]
    assert_equal "Test Episode", enqueued_args[:metadata][:title]
    assert_equal "Test Author", enqueued_args[:metadata][:author]
    assert_equal "Test Description", enqueued_args[:metadata][:description]
  end

  test "does not upload or enqueue when episode save fails" do
    upload_called = false
    enqueue_called = false

    @mock_uploader.define_singleton_method(:upload_staging_file) do |content:, filename:|
      upload_called = true
      "staging/#{filename}"
    end
    @mock_enqueuer.define_singleton_method(:enqueue_episode_processing) do |**args|
      enqueue_called = true
      nil
    end

    invalid_params = { title: "", author: "", description: "" }

    result = EpisodeSubmissionService.new(
      podcast: @podcast,
      params: invalid_params,
      uploaded_file: @uploaded_file,
      gcs_uploader: @mock_uploader,
      enqueuer: @mock_enqueuer
    ).call

    assert result.failure?
    assert_not upload_called, "Should not upload when save fails"
    assert_not enqueue_called, "Should not enqueue when save fails"
  end

  test "class method call delegates to instance" do
    @mock_uploader.define_singleton_method(:upload_staging_file) { |content:, filename:| "staging/#{filename}" }
    @mock_enqueuer.define_singleton_method(:enqueue_episode_processing) { |**args| nil }

    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"

    GcsUploader.stub :new, @mock_uploader do
      CloudTasksEnqueuer.stub :new, @mock_enqueuer do
        result = EpisodeSubmissionService.call(
          podcast: @podcast,
          params: @params,
          uploaded_file: @uploaded_file
        )

        assert result.success?
        assert result.episode.persisted?
      end
    end
  ensure
    ENV.delete("GOOGLE_CLOUD_BUCKET")
  end
end
