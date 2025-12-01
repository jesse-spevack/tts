# frozen_string_literal: true

class LlmClient
  DEFAULT_MODEL = "gemini-2.0-flash"
  PROVIDER = :vertexai

  def initialize(model: DEFAULT_MODEL)
    @model = model
  end

  def ask(prompt)
    Rails.logger.info "event=llm_client_ask model=#{model} provider=#{PROVIDER}"

    RubyLLM.chat(model: model, provider: PROVIDER).ask(prompt)
  end

  def find_model(model_id)
    RubyLLM.models.find(model_id)
  end

  private

  attr_reader :model
end
