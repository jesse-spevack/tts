# frozen_string_literal: true

class CreatesExtensionEpisode
  include StructuredLogging

  def self.call(podcast:, user:, title:, content:, url:, author:, description:)
    new(
      podcast: podcast,
      user: user,
      title: title,
      content: content,
      url: url,
      author: author,
      description: description
    ).call
  end

  def initialize(podcast:, user:, title:, content:, url:, author:, description:)
    @podcast = podcast
    @user = user
    @title = title
    @content = content
    @url = url
    @author = author
    @description = description
  end

  def call
    plain_text = StripsMarkdown.call(content)

    episode = podcast.episodes.create(
      user: user,
      title: title,
      author: author.presence || extract_domain_from_url,
      description: description,
      source_type: :extension,
      source_url: url,
      source_text: content,
      content_preview: GeneratesContentPreview.call(plain_text),
      status: :processing
    )

    return Result.failure(episode.errors.full_messages.first) unless episode.persisted?

    ProcessesFileEpisodeJob.perform_later(
      episode_id: episode.id,
      user_id: episode.user_id,
      action_id: Current.action_id
    )

    log_info "extension_episode_created",
             episode_id: episode.id,
             url: url,
             content_length: content.length

    Result.success(episode)
  end

  private

  attr_reader :podcast, :user, :title, :content, :url, :author, :description

  def extract_domain_from_url
    URI.parse(url).host&.gsub(/^www\./, "") || "Unknown"
  rescue URI::InvalidURIError
    "Unknown"
  end
end
