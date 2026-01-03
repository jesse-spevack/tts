# frozen_string_literal: true

class CreateUrlEpisode
  UNSUPPORTED_HOSTS = %w[twitter.com x.com].freeze

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
    return Result.failure(unsupported_site_message) if unsupported_site?

    Rails.logger.info "event=url_normalization_started url=#{url}"
    normalize_result = NormalizesSubstackUrl.call(url: url)
    return normalize_result if normalize_result.failure?

    @normalized_url = normalize_result.data

    episode = create_episode
    return Result.failure(episode.errors.full_messages.first) unless episode.persisted?

    ProcessUrlEpisodeJob.perform_later(episode_id: episode.id, user_id: episode.user_id)

    Rails.logger.info "event=url_episode_created episode_id=#{episode.id} url=#{@normalized_url}"

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :url

  def valid_url?
    ValidatesUrl.valid?(url)
  end

  def unsupported_site?
    host = URI.parse(url).host&.downcase
    UNSUPPORTED_HOSTS.any? { |h| host == h || host&.end_with?(".#{h}") }
  rescue URI::InvalidURIError
    false
  end

  def unsupported_site_message
    "Twitter/X links aren't supported — copy and paste the tweet text instead"
  end

  def create_episode
    podcast.episodes.create(
      user: user,
      title: EpisodePlaceholders::TITLE,
      author: EpisodePlaceholders::AUTHOR,
      description: EpisodePlaceholders.description_for(:url),
      source_type: :url,
      source_url: @normalized_url,
      status: :processing
    )
  end
end
