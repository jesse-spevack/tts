class ProcessUrlEpisode
  def self.call(episode:, gcs_uploader: nil, tasks_enqueuer: nil)
    new(
      episode: episode,
      gcs_uploader: gcs_uploader,
      tasks_enqueuer: tasks_enqueuer
    ).call
  end

  def initialize(episode:, gcs_uploader: nil, tasks_enqueuer: nil)
    @episode = episode
    @user = episode.user
    @gcs_uploader = gcs_uploader
    @tasks_enqueuer = tasks_enqueuer
  end

  def call
    Rails.logger.info "event=process_url_episode_started episode_id=#{episode.id} url=#{episode.source_url}"

    fetch_url
    extract_content
    check_character_limit
    process_with_llm
    update_episode_metadata
    upload_and_enqueue

    Rails.logger.info "event=process_url_episode_completed episode_id=#{episode.id}"
  rescue ProcessingError => e
    fail_episode(e.message)
  rescue StandardError => e
    Rails.logger.error "event=process_url_episode_error episode_id=#{episode.id} error=#{e.class} message=#{e.message}"
    fail_episode(e.message)
  end

  private

  attr_reader :episode, :user

  def fetch_url
    Rails.logger.info "event=url_fetch_started episode_id=#{episode.id} url=#{episode.source_url}"
    @fetch_result = UrlFetcher.call(url: episode.source_url)
    if @fetch_result.failure?
      Rails.logger.warn "event=url_fetch_failed episode_id=#{episode.id} error=#{@fetch_result.error}"
      raise ProcessingError, @fetch_result.error
    end
    Rails.logger.info "event=url_fetch_completed episode_id=#{episode.id} bytes=#{@fetch_result.html.bytesize}"
  end

  def extract_content
    Rails.logger.info "event=article_extraction_started episode_id=#{episode.id}"
    @extract_result = ArticleExtractor.call(html: @fetch_result.html)
    if @extract_result.failure?
      Rails.logger.warn "event=article_extraction_failed episode_id=#{episode.id} error=#{@extract_result.error}"
      raise ProcessingError, @extract_result.error
    end
    Rails.logger.info "event=article_extraction_completed episode_id=#{episode.id} characters=#{@extract_result.character_count}"
  end

  def check_character_limit
    max_chars = max_characters_for(user)
    return unless max_chars && @extract_result.character_count > max_chars

    Rails.logger.warn "event=character_limit_exceeded episode_id=#{episode.id} characters=#{@extract_result.character_count} limit=#{max_chars} tier=#{user.tier}"
    raise ProcessingError, "This content is too long for your account tier"
  end

  def process_with_llm
    Rails.logger.info "event=llm_processing_started episode_id=#{episode.id} characters=#{@extract_result.character_count}"
    @llm_result = LlmProcessor.call(text: @extract_result.text, episode: episode, user: user)
    if @llm_result.failure?
      Rails.logger.warn "event=llm_processing_failed episode_id=#{episode.id} error=#{@llm_result.error}"
      raise ProcessingError, @llm_result.error
    end
    Rails.logger.info "event=llm_processing_completed episode_id=#{episode.id} title=#{@llm_result.title}"
  end

  def update_episode_metadata
    episode.update!(
      title: @llm_result.title,
      author: @llm_result.author,
      description: @llm_result.description
    )
    Rails.logger.info "event=episode_metadata_updated episode_id=#{episode.id}"
  end

  def upload_and_enqueue
    staging_path = upload_to_staging(@llm_result.content)
    Rails.logger.info "event=content_uploaded episode_id=#{episode.id} staging_path=#{staging_path}"
    enqueue_processing(staging_path)
    Rails.logger.info "event=processing_enqueued episode_id=#{episode.id}"
  end

  def fail_episode(error_message)
    episode.update!(status: :failed, error_message: error_message)
    Rails.logger.warn "event=episode_marked_failed episode_id=#{episode.id} error=#{error_message}"
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

  class ProcessingError < StandardError; end
end
