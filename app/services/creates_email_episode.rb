# frozen_string_literal: true

class CreatesEmailEpisode
  include StructuredLogging

  def self.call(user:, email_body:)
    new(user: user, email_body: email_body).call
  end

  def initialize(user:, email_body:)
    @user = user
    @email_body = email_body
  end

  def call
    podcast = user.primary_podcast

    episode = podcast.episodes.create(
      user: user,
      title: EpisodePlaceholders::TITLE,
      author: EpisodePlaceholders::AUTHOR,
      description: EpisodePlaceholders.description_for(:email),
      source_type: :email,
      source_text: email_body,
      status: :processing
    )

    return Result.failure(episode.errors.full_messages.first) unless episode.persisted?

    ProcessesEmailEpisodeJob.set(priority: DeterminesJobPriority.call(user: user)).perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
    log_info "email_episode_created", episode_id: episode.id, text_length: email_body.length

    Result.success(episode)
  end

  private

  attr_reader :user, :email_body
end
