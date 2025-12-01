class ProcessUrlEpisode
  def self.call(episode:, gcs_uploader: nil, tasks_enqueuer: nil, llm_processor: nil)
    new(
      episode: episode,
      gcs_uploader: gcs_uploader,
      tasks_enqueuer: tasks_enqueuer,
      llm_processor: llm_processor
    ).call
  end

  def initialize(episode:, gcs_uploader: nil, tasks_enqueuer: nil, llm_processor: nil)
    @episode = episode
    @user = episode.user
    @gcs_uploader = gcs_uploader
    @tasks_enqueuer = tasks_enqueuer
    @llm_processor = llm_processor
  end

  def call
    fetch_url
    extract_content
    check_character_limit
    process_with_llm
    update_episode_metadata
    upload_and_enqueue

    Rails.logger.info "event=url_episode_processed episode_id=#{episode.id}"
  rescue ProcessingError => e
    fail_episode(e.message)
  rescue StandardError => e
    Rails.logger.error "event=url_episode_failed episode_id=#{episode.id} error=#{e.message}"
    fail_episode(e.message)
  end

  private

  attr_reader :episode, :user

  def fetch_url
    @fetch_result = UrlFetcher.call(url: episode.source_url)
    raise ProcessingError, @fetch_result.error if @fetch_result.failure?
  end

  def extract_content
    @extract_result = ArticleExtractor.call(html: @fetch_result.html)
    raise ProcessingError, @extract_result.error if @extract_result.failure?
  end

  def check_character_limit
    max_chars = max_characters_for(user)
    return unless max_chars && @extract_result.character_count > max_chars

    raise ProcessingError, "This content is too long for your account tier"
  end

  def process_with_llm
    @llm_result = llm_processor.call(text: @extract_result.text, episode: episode, user: user)
    raise ProcessingError, @llm_result.error if @llm_result.failure?
  end

  def update_episode_metadata
    episode.update!(
      title: @llm_result.title,
      author: @llm_result.author,
      description: @llm_result.description
    )
  end

  def upload_and_enqueue
    staging_path = upload_to_staging(@llm_result.content)
    enqueue_processing(staging_path)
  end

  def fail_episode(error_message)
    episode.update!(status: :failed, error_message: error_message)
    Rails.logger.info "event=url_episode_failed episode_id=#{episode.id} error=#{error_message}"
  end

  def max_characters_for(user)
    case user.tier
    when "free" then EpisodeSubmissionValidator::MAX_CHARACTERS_FREE
    when "premium" then EpisodeSubmissionValidator::MAX_CHARACTERS_PREMIUM
    when "unlimited" then nil
    end
  end

  def upload_to_staging(content)
    filename = "#{episode.id}-#{Time.now.to_i}.md"
    gcs_uploader.upload_staging_file(content: content, filename: filename)
  end

  def enqueue_processing(staging_path)
    tasks_enqueuer.enqueue_episode_processing(
      episode_id: episode.id,
      podcast_id: episode.podcast.podcast_id,
      staging_path: staging_path,
      metadata: {
        title: episode.title,
        author: episode.author,
        description: episode.description
      },
      voice_name: user.voice_name
    )
  end

  def gcs_uploader
    @gcs_uploader ||= GcsUploader.new(
      ENV.fetch("GOOGLE_CLOUD_BUCKET"),
      podcast_id: episode.podcast.podcast_id
    )
  end

  def tasks_enqueuer
    @tasks_enqueuer ||= CloudTasksEnqueuer.new
  end

  def llm_processor
    @llm_processor ||= LlmProcessor
  end

  class ProcessingError < StandardError; end
end
