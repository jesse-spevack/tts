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

    input_cost_cents = BigDecimal(response.input_tokens) * BigDecimal(info.input_price_per_million.to_s) / 10_000
    output_cost_cents = BigDecimal(response.output_tokens) * BigDecimal(info.output_price_per_million.to_s) / 10_000
    total_cost_cents = input_cost_cents + output_cost_cents

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
    @llm_client ||= AsksLlm.new
  end
end
