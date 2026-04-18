# frozen_string_literal: true

class ProcessesNarrationJob < ApplicationJob
  queue_as :default

  def perform(narration_id:)
    narration = Narration.find(narration_id)
    ProcessesNarration.call(narration: narration)
  end
end
