# frozen_string_literal: true

class CreatesFileEpisode
  include StructuredLogging

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
    plain_text = StripsMarkdown.call(content)

    episode = podcast.episodes.create(
      user: user,
      title: title,
      author: author,
      description: description,
      source_type: :file,
      source_text: content,
      content_preview: GeneratesContentPreview.call(plain_text),
      status: :processing
    )

    return Result.failure(episode.errors.full_messages.first) unless episode.persisted?

    ProcessesFileEpisodeJob.perform_later(episode_id: episode.id, user_id: episode.user_id, action_id: Current.action_id)
    log_info "file_episode_created", episode_id: episode.id, content_length: content.length

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :title, :author, :description, :content
end
