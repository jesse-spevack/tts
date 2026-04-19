# frozen_string_literal: true

class GeneratesNarrationAudioUrl
  def self.call(narration)
    new(narration).call
  end

  def initialize(narration)
    @narration = narration
  end

  def call
    return nil unless narration.complete? && narration.gcs_episode_id.present?

    "#{AppConfig::Storage::BASE_URL}/narrations/#{narration.gcs_episode_id}.mp3"
  end

  private

  attr_reader :narration
end
