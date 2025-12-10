class ProcessPasteEpisodeJob < ApplicationJob
  queue_as :default

  def perform(episode_id)
    # Implementation in next task
  end
end
