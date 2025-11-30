class EpisodeSubmissionService
  def self.call(podcast:, user:, params:, uploaded_file:, max_characters: nil, voice_name: nil)
    new(podcast: podcast, user: user, params: params, uploaded_file: uploaded_file, max_characters: max_characters, voice_name: voice_name).call
  end

  def initialize(podcast:, user:, params:, uploaded_file:, max_characters: nil, voice_name: nil, gcs_uploader: nil, enqueuer: nil)
    @podcast = podcast
    @user = user
    @voice_name = voice_name
    @params = params
    @uploaded_file = uploaded_file
    @max_characters = max_characters
    @gcs_uploader = gcs_uploader
    @enqueuer = enqueuer
  end

  def call
    unless uploaded_file&.respond_to?(:read)
      episode = build_episode
      episode.status = "failed"
      episode.error_message = "No file uploaded"
      episode.save
      Rails.logger.error "event=episode_submission_failed episode_id=#{episode.id} error_class=ValidationError error_message=\"No file uploaded\""
      return Result.failure(episode)
    end

    if max_characters
      validation_result = validate_file_size(max_characters)
      return validation_result if validation_result
    end

    episode = build_episode
    return Result.failure(episode) unless episode.save

    Rails.logger.info "event=episode_created episode_id=#{episode.id} podcast_id=#{podcast.podcast_id} user_id=#{user.id} title=\"#{episode.title}\""

    staging_path = upload_to_staging(episode)
    enqueue_processing(episode, staging_path)

    Result.success(episode)
  rescue Google::Cloud::Error => e
    Rails.logger.error "event=gcs_upload_failed episode_id=#{episode&.id} error_class=#{e.class} error_message=\"#{e.message}\""
    episode&.update(status: "failed", error_message: "Failed to upload to staging: #{e.message}")
    Result.failure(episode)
  rescue StandardError => e
    Rails.logger.error "event=episode_submission_failed episode_id=#{episode&.id} error_class=#{e.class} error_message=\"#{e.message}\""
    episode&.update(status: "failed", error_message: e.message)
    Result.failure(episode)
  end

  private

  attr_reader :podcast, :user, :params, :uploaded_file, :max_characters, :voice_name

  def build_episode
    podcast.episodes.build(
      user: user,
      title: params[:title],
      author: params[:author],
      description: params[:description]
    )
  end

  def upload_to_staging(episode)
    content = uploaded_file.read
    filename = "#{episode.id}-#{Time.now.to_i}.md"

    staging_path = gcs_uploader.upload_staging_file(content: content, filename: filename)

    Rails.logger.info "event=staging_uploaded episode_id=#{episode.id} staging_path=#{staging_path} size_bytes=#{content.bytesize}"

    staging_path
  end

  def enqueue_processing(episode, staging_path)
    task_name = enqueuer.enqueue_episode_processing(
      episode_id: episode.id,
      podcast_id: podcast.podcast_id,
      staging_path: staging_path,
      metadata: {
        title: episode.title,
        author: episode.author,
        description: episode.description
      },
      voice_name: voice_name
    )

    Rails.logger.info "event=task_enqueued episode_id=#{episode.id} podcast_id=#{podcast.podcast_id} task_name=#{task_name}"
  end

  def gcs_uploader
    @gcs_uploader ||= GcsUploader.new(
      ENV.fetch("GOOGLE_CLOUD_BUCKET"),
      podcast_id: podcast.podcast_id
    )
  end

  def enqueuer
    @enqueuer ||= CloudTasksEnqueuer.new
  end

  def validate_file_size(limit)
    content = uploaded_file.read
    uploaded_file.rewind

    return unless content.length > limit

    episode = build_episode
    episode.errors.add(
      :content,
      "is too large (#{ActiveSupport::NumberHelper.number_to_delimited(content.length)} characters). Maximum: #{ActiveSupport::NumberHelper.number_to_delimited(limit)} characters."
    )
    Rails.logger.info "event=file_size_rejected episode_title=\"#{params[:title]}\" size=#{content.length} limit=#{limit}"
    Result.failure(episode)
  end

  class Result
    attr_reader :episode

    def self.success(episode)
      new(episode: episode, success: true)
    end

    def self.failure(episode)
      new(episode: episode, success: false)
    end

    def initialize(episode:, success:)
      @episode = episode
      @success = success
    end

    def success?
      @success
    end

    def failure?
      !@success
    end
  end
end
