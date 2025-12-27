# frozen_string_literal: true

class DeleteEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode)
    DeleteEpisode.call(episode: episode)
  end
end
