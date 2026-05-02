# frozen_string_literal: true

class AsksLlm
  include StructuredLogging

  # NOTE: The structured output config below (generationConfig with responseSchema)
  # is Gemini-specific. If switching to a different provider, update the ask method.
  DEFAULT_MODEL = "gemini-2.5-flash"
  PROVIDER = :vertexai

  # JSON schema for structured output - guarantees valid JSON responses
  RESPONSE_SCHEMA = {
    type: "object",
    properties: {
      title: { type: "string", description: "The title of the article" },
      author: { type: "string", description: "The author of the article" },
      description: { type: "string", description: "A brief description of the article" },
      content: { type: "string", description: "The full article content, cleaned and formatted for text-to-speech" }
    },
    required: %w[title author description content]
  }.freeze

  def initialize(model: DEFAULT_MODEL)
    @model = model
  end

  def ask(prompt)
    log_info "asks_llm", model: model, provider: PROVIDER

    RubyLLM.chat(model: model, provider: PROVIDER)
      .with_params(generationConfig: {
        responseMimeType: "application/json",
        responseSchema: RESPONSE_SCHEMA
      })
      .ask(prompt)
  end

  def find_model(model_id)
    RubyLLM.models.find(model_id)
  end

  private

  attr_reader :model
end
