# frozen_string_literal: true

module Simulates
  module AsksLlm
    include StructuredLogging

    SimulatedResponse = Data.define(:content, :input_tokens, :output_tokens, :model_id)
    SimulatedModelInfo = Data.define(:input_price_per_million, :output_price_per_million)

    def find_model(_model_id)
      SimulatedModelInfo.new(input_price_per_million: 0, output_price_per_million: 0)
    end

    def ask(prompt)
      log_info "simulation_llm_started", prompt_length: prompt.length

      sleep(rand(1.0..3.0))

      title = extract_title(prompt)
      description = prompt[0, 200]

      json_response = JSON.generate(
        title: title,
        author: "Simulation Mode",
        description: description,
        content: prompt
      )

      log_info "simulation_llm_completed", response_length: json_response.length

      SimulatedResponse.new(
        content: json_response,
        input_tokens: prompt.length,
        output_tokens: json_response.length,
        model_id: "simulated"
      )
    end

    private

    def extract_title(prompt)
      first_chunk = prompt.split(/[.\n]/).first&.strip
      return "Simulated Episode" if first_chunk.blank?

      first_chunk.truncate(80)
    end
  end
end
