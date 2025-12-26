# frozen_string_literal: true

class SubmitEpisodeForProcessing
  def self.call(episode:, content:)
    new(episode: episode, content: content).call
  end

  def initialize(episode:, content:)
    @episode = episode
    @content = content
  end

  def call
    Rails.logger.info "event=submit_episode_for_processing episode_id=#{episode.id} podcast_id=#{episode.podcast.podcast_id}"

    wrapped = wrap_content
    episode.update!(source_text: wrapped)

    GenerateAudioJob.perform_later(episode)

    Rails.logger.info "event=processing_enqueued episode_id=#{episode.id}"
  end

  private

  attr_reader :episode, :content

  def wrap_content
    BuildEpisodeWrapper.call(
      title: episode.title,
      author: episode.author,
      tier: episode.user.tier,
      content: content
    )
  end
end
