# frozen_string_literal: true

class ProcessesFileEpisode
  include EpisodeErrorHandling

  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
  end

  def call
    log_info "process_file_episode_started", text_length: episode.source_text.length

    content = strip_markdown
    submit_for_processing(content)

    log_info "process_file_episode_completed"
  rescue StandardError => e
    log_error "process_file_episode_error", error: e.class, message: e.message
    fail_episode(e.message)
  end

  private

  attr_reader :episode

  def strip_markdown
    StripsMarkdown.call(episode.source_text)
  end

  def submit_for_processing(content)
    SubmitsEpisodeForProcessing.call(episode: episode, content: content)
  end
end
