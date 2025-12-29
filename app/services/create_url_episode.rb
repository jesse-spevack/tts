# frozen_string_literal: true

class CreateUrlEpisode
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

    episode = create_episode
    return Result.failure(episode.errors.full_messages.first) unless episode.persisted?

    ProcessUrlEpisodeJob.perform_later(episode.id)

    Rails.logger.info "event=url_episode_created episode_id=#{episode.id} url=#{url}"

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :url

  def valid_url?
    ValidatesUrl.valid?(url)
  end

  def create_episode
    podcast.episodes.create(
      user: user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing article from URL...",
      source_type: :url,
      source_url: url,
      status: :processing
    )
  end
end
