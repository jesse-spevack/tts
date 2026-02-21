# frozen_string_literal: true

module Simulation
  module SynthesizesAudio
    include StructuredLogging

    def call(text:, voice: nil)
      sleep_seconds = EstimatesProcessingTime.call(source_text_length: text.length)

      log_info "simulation_tts_started", text_length: text.length, sleep_seconds: sleep_seconds
      sleep(sleep_seconds)
      log_info "simulation_tts_completed"

      Rails.root.join("test/fixtures/files/silence.mp3").binread
    end
  end
end
