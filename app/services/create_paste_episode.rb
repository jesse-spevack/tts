# frozen_string_literal: true

class CreatePasteEpisode
  def self.call(podcast:, user:, text:)
    new(podcast: podcast, user: user, text: text).call
  end

  def initialize(podcast:, user:, text:)
    @podcast = podcast
    @user = user
    @text = text
  end

  def call
    episode = podcast.episodes.create(
      user: user,
      title: EpisodePlaceholders::TITLE,
      author: EpisodePlaceholders::AUTHOR,
      description: EpisodePlaceholders.description_for(:paste),
      source_type: :paste,
      source_text: text,
      status: :processing
    )

    return Result.failure(episode.errors.full_messages.first) unless episode.persisted?

    ProcessPasteEpisodeJob.perform_later(episode_id: episode.id, user_id: episode.user_id)
    Rails.logger.info "event=paste_episode_created episode_id=#{episode.id} text_length=#{text.length}"

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :text
end
