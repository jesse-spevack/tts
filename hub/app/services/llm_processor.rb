class LlmProcessor
  MODEL = "vertex_ai/claude-3-haiku@20240307"

  def self.call(text:, episode:, user:, chat_client: nil, models_registry: nil)
    new(text: text, episode: episode, user: user, chat_client: chat_client, models_registry: models_registry).call
  end

  def initialize(text:, episode:, user:, chat_client: nil, models_registry: nil)
    @text = text
    @episode = episode
    @user = user
    @chat_client = chat_client
    @models_registry = models_registry
  end

  def call
    prompt = UrlProcessingPrompt.build(text: text)
    response = chat_response(prompt)
    parsed = parse_response(response.content)

    record_usage(response)

    Result.success(
      title: parsed["title"],
      author: parsed["author"],
      description: parsed["description"],
      content: parsed["content"]
    )
  rescue RubyLLM::Error, JSON::ParserError => e
    Rails.logger.error "event=llm_processing_failed episode_id=#{episode.id} error=#{e.message}"
    Result.failure("Failed to process content")
  end

  private

  attr_reader :text, :episode, :user, :chat_client, :models_registry

  def chat_response(prompt)
    client = chat_client || RubyLLM.chat(model: MODEL)
    client.ask(prompt)
  end

  def parse_response(content)
    # Strip markdown code blocks if present
    json_content = content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip
    JSON.parse(json_content)
  end

  def record_usage(response)
    registry = models_registry || RubyLLM.models
    info = registry.find(response.model_id)

    input_cost = response.input_tokens * info.input_price_per_million / 1_000_000
    output_cost = response.output_tokens * info.output_price_per_million / 1_000_000
    total_cost_cents = (input_cost + output_cost) * 100

    LlmUsage.create!(
      episode: episode,
      model_id: response.model_id,
      provider: "vertex_ai",
      input_tokens: response.input_tokens,
      output_tokens: response.output_tokens,
      cost_cents: total_cost_cents
    )
  end

  class Result
    attr_reader :title, :author, :description, :content, :error

    def self.success(title:, author:, description:, content:)
      new(title: title, author: author, description: description, content: content, error: nil)
    end

    def self.failure(error)
      new(title: nil, author: nil, description: nil, content: nil, error: error)
    end

    def initialize(title:, author:, description:, content:, error:)
      @title = title
      @author = author
      @description = description
      @content = content
      @error = error
    end

    def success?
      error.nil?
    end

    def failure?
      !success?
    end
  end
end
