# frozen_string_literal: true

class LlmClient
  DEFAULT_MODEL = "gemini-2.0-flash"
  PROVIDER = :vertexai

  def initialize(model: DEFAULT_MODEL)
    @model = model
  end

  def ask(prompt)
    Rails.logger.info "event=llm_client_ask model=#{model} provider=#{PROVIDER}"

    # Gemini 2.0 Flash has a low default output limit (8,192 tokens) which truncates
    # long articles. Override to 65k. Can be removed when upgrading to Gemini 2.5 Flash
    # which defaults to 65k.
    RubyLLM.chat(model: model, provider: PROVIDER)
      .with_params(generationConfig: { maxOutputTokens: 65_536 })
      .ask(prompt)
  end

  def find_model(model_id)
    RubyLLM.models.find(model_id)
  end

  private

  attr_reader :model
end
