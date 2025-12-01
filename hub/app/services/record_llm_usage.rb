# frozen_string_literal: true

class RecordLlmUsage
  def self.call(episode:, response:)
    new(episode: episode, response: response).call
  end

  def initialize(episode:, response:)
    @episode = episode
    @response = response
  end

  def call
    info = llm_client.find_model(response.model_id)

    input_cost = response.input_tokens * info.input_price_per_million / 1_000_000
    output_cost = response.output_tokens * info.output_price_per_million / 1_000_000
    total_cost_cents = (input_cost + output_cost) * 100

    usage = LlmUsage.create!(
      episode: episode,
      model_id: response.model_id,
      provider: "vertex_ai",
      input_tokens: response.input_tokens,
      output_tokens: response.output_tokens,
      cost_cents: total_cost_cents
    )

    Rails.logger.info "event=llm_usage_recorded llm_usage_id=#{usage.id} episode_id=#{episode.id} model=#{response.model_id} cost_cents=#{total_cost_cents.round(4)}"

    usage
  end

  private

  attr_reader :episode, :response

  def llm_client
    @llm_client ||= LlmClient.new
  end
end
