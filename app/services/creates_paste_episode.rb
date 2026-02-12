# frozen_string_literal: true

class CreatesPasteEpisode
  include StructuredLogging

  def self.call(podcast:, user:, text:, title: nil, author: nil)
    new(podcast: podcast, user: user, text: text, title: title, author: author).call
  end

  def initialize(podcast:, user:, text:, title: nil, author: nil)
    @podcast = podcast
    @user = user
    @text = text
    @title = title.presence
    @author = author.presence
  end

  def call
    episode = podcast.episodes.create(
      user: user,
      title: @title || EpisodePlaceholders::TITLE,
      author: @author || EpisodePlaceholders::AUTHOR,
      description: EpisodePlaceholders.description_for(:paste),
      source_type: :paste,
      source_text: text,
      status: :processing
    )

    return Result.failure(episode.errors.full_messages.first) unless episode.persisted?

    ProcessesPasteEpisodeJob.set(priority: DeterminesJobPriority.call(user: user)).perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
    log_info "paste_episode_created", episode_id: episode.id, text_length: text.length

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :text
end
