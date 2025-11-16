class EpisodeSubmissionService
  def self.call(podcast:, params:, uploaded_file:)
    new(podcast: podcast, params: params, uploaded_file: uploaded_file).call
  end

  def initialize(podcast:, params:, uploaded_file:, gcs_uploader: nil, enqueuer: nil)
    @podcast = podcast
    @params = params
    @uploaded_file = uploaded_file
    @gcs_uploader = gcs_uploader
    @enqueuer = enqueuer
  end

  def call
    episode = build_episode
    return Result.failure(episode) unless episode.save

    Rails.logger.info "event=episode_created episode_id=#{episode.id} podcast_id=#{podcast.podcast_id} user_id=#{podcast.users.first.id} title=\"#{episode.title}\""

    staging_path = upload_to_staging(episode)
    enqueue_processing(episode, staging_path)

    Result.success(episode)
  end

  private

  attr_reader :podcast, :params, :uploaded_file

  def build_episode
    podcast.episodes.build(
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
    enqueuer.enqueue_episode_processing(
      episode_id: episode.id,
      podcast_id: podcast.podcast_id,
      staging_path: staging_path,
      metadata: {
        title: episode.title,
        author: episode.author,
        description: episode.description
      }
    )
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
