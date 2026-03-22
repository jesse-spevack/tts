# frozen_string_literal: true

class CreatesUrlEpisode
  include StructuredLogging

  def self.call(podcast:, user:, url:)
    new(podcast: podcast, user: user, url: url).call
  end

  def initialize(podcast:, user:, url:)
    @podcast = podcast
    @user = user
    @url = url
  end

  def call
    return Result.failure("Invalid URL") unless valid_url?

    log_info "url_normalization_started", url: url

    normalized = normalize_url
    return normalized if normalized.failure?

    @normalized_url = StripsUrlTrackingParams.call(normalized.data)

    episode = create_episode
    return Result.failure(episode.errors.full_messages.first) unless episode.persisted?

    ProcessesUrlEpisodeJob.set(priority: DeterminesJobPriority.call(user: user)).perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)

    log_info "url_episode_created", episode_id: episode.id, url: @normalized_url

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :url

  def valid_url?
    ValidatesUrl.call(url)
  end

  def normalize_url
    if NormalizesTwitterUrl.twitter_url?(url)
      NormalizesTwitterUrl.call(url: url)
    else
      NormalizesSubstackUrl.call(url: url)
    end
  end

  def create_episode
    podcast.episodes.create(
      user: user,
      title: EpisodePlaceholders::TITLE,
      author: EpisodePlaceholders::AUTHOR,
      description: EpisodePlaceholders.description_for(:url),
      source_type: :url,
      source_url: @normalized_url,
      status: :pending
    )
  end
end
