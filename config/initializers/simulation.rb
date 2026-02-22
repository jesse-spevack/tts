# frozen_string_literal: true

Rails.application.config.simulation_mode = ENV["SIMULATE_EXTERNAL"] == "true"

if Rails.application.config.simulation_mode
  Rails.application.config.after_initialize do
    SynthesizesAudio.prepend(Simulates::SynthesizesAudio)
    AsksLlm.prepend(Simulates::AsksLlm)
    CloudStorage.prepend(Simulates::CloudStorage)
    FetchesUrl.prepend(Simulates::FetchesUrl)
    FetchesJinaContent.prepend(Simulates::FetchesJinaContent)

    Rails.logger.warn(
      "\e[33m⚠️  Simulation mode active — external services mocked (GCP TTS, Gemini, Cloud Storage, URL fetching)\e[0m"
    )
  end
end
