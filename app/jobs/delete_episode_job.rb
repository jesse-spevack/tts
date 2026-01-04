# frozen_string_literal: true

class DeleteEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode:, action_id: nil)
    Current.action_id = action_id || SecureRandom.uuid
    DeleteEpisode.call(episode: episode)
  end
end
