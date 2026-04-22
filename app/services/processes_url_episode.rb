# frozen_string_literal: true

class ProcessesUrlEpisode
  include EpisodeErrorHandling

  def self.call(episode:, voice_override: nil)
    new(episode: episode, voice_override: voice_override).call
  end

  def initialize(episode:, voice_override: nil)
    @episode = episode
    @user = episode.user
    @voice_override = voice_override
  end

  def call
    log_info "process_url_episode_started", url: episode.source_url

    episode.update!(status: :preparing)
    fetch_and_extract
    check_character_limit
    deduct_credit
    process_with_llm
    update_and_enqueue

    log_info "process_url_episode_completed"
  rescue EpisodeErrorHandling::ProcessingError => e
    fail_episode(e.message)
  rescue StandardError => e
    log_error "process_url_episode_error", error: e.class, message: e.message, exception: e

    fail_episode(e.message)
  end

  private

  attr_reader :episode, :user

  def fetch_and_extract
    @extract_result = FetchesArticleContent.call(url: episode.source_url)

    if @extract_result.failure?
      raise EpisodeErrorHandling::ProcessingError, @extract_result.error
    end
  end

  def check_character_limit
    result = ValidatesCharacterLimit.call(
      user: user,
      character_count: @extract_result.data.character_count
    )

    return if result.success?

    log_warn "character_limit_exceeded",
      characters: @extract_result.data.character_count,
      limit: user.character_limit

    raise EpisodeErrorHandling::ProcessingError, result.error
  end

  # URL credit debit runs here rather than at controller-submit time,
  # because the article length isn't known until after FetchesUrl +
  # ExtractsArticle. Without this the controller would uniformly debit
  # 1 credit, under-charging Premium voice + >20k articles.
  def deduct_credit
    if user.complimentary? || user.unlimited? || user.free?
      episode.update!(credit_cost: 0)
      return
    end

    cost = CalculatesAnticipatedEpisodeCost.call(
      EpisodeCostRequest.new(
        user: user,
        source_type: "url",
        source_text_length: @extract_result.data.character_count
      )
    ).data

    result = DeductsCredit.call(user: user, episode: episode, cost_in_credits: cost.credits)
    if result.success?
      episode.update!(credit_cost: cost.credits)
      return
    end

    log_warn "insufficient_credits_for_url_episode",
      cost: cost.credits,
      balance: user.credits_remaining

    raise EpisodeErrorHandling::ProcessingError,
      "Insufficient credits: this article needs #{cost.credits} #{'credit'.pluralize(cost.credits)} " \
      "but you have #{user.credits_remaining}. Buy more at " \
      "#{AppConfig::Domain::BASE_URL}/billing"
  end

  def process_with_llm
    log_info "llm_processing_started", characters: @extract_result.data.character_count

    @llm_result = ProcessesWithLlm.call(text: @extract_result.data.text, episode: episode)
    if @llm_result.failure?
      log_warn "llm_processing_failed", error: @llm_result.error

      raise EpisodeErrorHandling::ProcessingError, @llm_result.error
    end

    log_info "llm_processing_completed", title: @llm_result.data.title
  end

  def update_and_enqueue
    content = @llm_result.data.content
    description = FormatsEpisodeDescription.call(
      description: @llm_result.data.description,
      source_url: episode.source_url
    )

    episode.update!(
      title: @extract_result.data.title || @llm_result.data.title,
      author: @extract_result.data.author || known_author || @llm_result.data.author,
      description: description,
      content_preview: GeneratesContentPreview.call(content),
      status: :preparing
    )

    log_info "episode_metadata_updated"

    SubmitsEpisodeForProcessing.call(episode: episode, content: content, voice_override: @voice_override)
  end

  def known_author
    host = URI.parse(episode.source_url).host&.downcase&.delete_prefix("www.")
    AppConfig::Content::KNOWN_AUTHORS[host]
  rescue URI::InvalidURIError
    nil
  end
end
