# frozen_string_literal: true

class ProcessesNarrationJob < ApplicationJob
  include NarrationJobLogging

  queue_as :default
  limits_concurrency to: 1, key: ->(narration_id:, **) { narration_id }

  def perform(narration_id:, action_id: nil)
    with_narration_logging(narration_id: narration_id, action_id: action_id) do
      narration = Narration.find(narration_id)
      ProcessesNarration.call(narration: narration)
    end
  end
end
