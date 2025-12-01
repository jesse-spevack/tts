# frozen_string_literal: true

class LlmClient
  DEFAULT_MODEL = "vertex_ai/claude-3-haiku@20240307"

  def initialize(model: DEFAULT_MODEL)
    @model = model
  end

  def ask(prompt)
    Rails.logger.info "event=llm_client_ask model=#{model}"
    RubyLLM.chat(model: model).ask(prompt)
  end

  def find_model(model_id)
    RubyLLM.models.find(model_id)
  end

  private

  attr_reader :model
end
