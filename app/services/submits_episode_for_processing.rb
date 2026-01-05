# frozen_string_literal: true

class SubmitsEpisodeForProcessing
  include EpisodeLogging

  def self.call(episode:, content:)
    new(episode: episode, content: content).call
  end

  def initialize(episode:, content:)
    @episode = episode
    @content = content
  end

  def call
    log_info "submit_episode_for_processing", podcast_id: episode.podcast.podcast_id

    wrapped = wrap_content
    episode.update!(source_text: wrapped)

    GeneratesEpisodeAudioJob.perform_later(episode_id: episode.id, action_id: Current.action_id)

    log_info "audio_generation_enqueued"
  end

  private

  attr_reader :episode, :content

  def wrap_content
    BuildsEpisodeWrapper.call(
      title: episode.title,
      author: episode.author,
      include_attribution: episode.user.free?,
      content: content
    )
  end
end
