# frozen_string_literal: true

if ENV["SIMULATE_EXTERNAL"] == "true"
  Rails.application.config.after_initialize do
    SynthesizesAudio.prepend(Simulation::SynthesizesAudio)
    AsksLlm.prepend(Simulation::AsksLlm)
    CloudStorage.prepend(Simulation::CloudStorage)

    Rails.logger.warn(
      "\e[33m⚠️  Simulation mode active — external services mocked (GCP TTS, Gemini, Cloud Storage)\e[0m"
    )
  end
end
