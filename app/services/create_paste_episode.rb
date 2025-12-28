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
    return Result.failure("Text cannot be empty") if text.blank?
    return Result.failure("Text must be at least #{AppConfig::Content::MIN_LENGTH} characters") if text.length < AppConfig::Content::MIN_LENGTH
    return Result.failure(max_characters_error) if exceeds_max_characters?

    episode = create_episode
    ProcessPasteEpisodeJob.perform_later(episode.id)

    Rails.logger.info "event=paste_episode_created episode_id=#{episode.id} text_length=#{text.length}"

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :text

  def exceeds_max_characters?
    max_chars = CalculatesMaxCharactersForUser.call(user: user)
    max_chars && text.length > max_chars
  end

  def max_characters_error
    max_chars = CalculatesMaxCharactersForUser.call(user: user)
    "Text is too long for your account tier (#{text.length} characters, max #{max_chars})"
  end

  def create_episode
    podcast.episodes.create!(
      user: user,
      title: "Processing...",
      author: "Processing...",
      description: "Processing pasted text...",
      source_type: :paste,
      source_text: text,
      status: :processing
    )
  end
end
