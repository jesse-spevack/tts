# frozen_string_literal: true

class CreateFileEpisode
  def self.call(podcast:, user:, title:, author:, description:, content:)
    new(podcast: podcast, user: user, title: title, author: author, description: description, content: content).call
  end

  def initialize(podcast:, user:, title:, author:, description:, content:)
    @podcast = podcast
    @user = user
    @title = title
    @author = author
    @description = description
    @content = content
  end

  def call
    return Result.failure("Content cannot be empty") if content.blank?
    return Result.failure(max_characters_error) if exceeds_max_characters?

    episode = create_episode
    ProcessFileEpisodeJob.perform_later(episode.id)

    Rails.logger.info "event=file_episode_created episode_id=#{episode.id} content_length=#{content.length}"

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :title, :author, :description, :content

  def exceeds_max_characters?
    max_chars = CalculatesMaxCharactersForUser.call(user: user)
    max_chars && content.length > max_chars
  end

  def max_characters_error
    max_chars = CalculatesMaxCharactersForUser.call(user: user)
    "Content is too long for your account tier (#{content.length} characters, max #{max_chars})"
  end

  def create_episode
    plain_text = StripsMarkdown.call(content)

    podcast.episodes.create!(
      user: user,
      title: title,
      author: author,
      description: description,
      source_type: :file,
      source_text: content,
      content_preview: GeneratesContentPreview.call(plain_text),
      status: :processing
    )
  end
end
