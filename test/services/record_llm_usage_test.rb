# frozen_string_literal: true

require "test_helper"
require "ostruct"

class RecordLlmUsageTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @response = OpenStruct.new(
      model_id: "claude-3-haiku-20240307",
      input_tokens: 1000,
      output_tokens: 500
    )

    Mocktail.replace(CallsLlm)
  end

  test "creates LlmUsage record with correct attributes" do
    stub_llm_client

    assert_difference -> { LlmUsage.count }, 1 do
      RecordLlmUsage.call(episode: @episode, response: @response)
    end

    usage = LlmUsage.last
    assert_equal @episode, usage.episode
    assert_equal "claude-3-haiku-20240307", usage.model_id
    assert_equal "vertex_ai", usage.provider
    assert_equal 1000, usage.input_tokens
    assert_equal 500, usage.output_tokens
  end

  test "calculates cost correctly" do
    stub_llm_client(input_price: 0.25, output_price: 1.25)

    RecordLlmUsage.call(episode: @episode, response: @response)

    usage = LlmUsage.last
    # Input: 1000 tokens * 0.25 / 1_000_000 = 0.00025
    # Output: 500 tokens * 1.25 / 1_000_000 = 0.000625
    # Total: 0.000875 dollars = 0.0875 cents
    assert_in_delta 0.0875, usage.cost_cents, 0.0001
  end

  test "returns the created usage record" do
    stub_llm_client

    result = RecordLlmUsage.call(episode: @episode, response: @response)

    assert_instance_of LlmUsage, result
    assert_equal @episode, result.episode
  end

  private

  def stub_llm_client(input_price: 0.25, output_price: 1.25)
    mock_model_info = OpenStruct.new(
      input_price_per_million: input_price,
      output_price_per_million: output_price
    )

    mock_client = Mocktail.of(CallsLlm)
    stubs { |m| mock_client.find_model(m.any) }.with { mock_model_info }
    stubs { CallsLlm.new }.with { mock_client }
  end
end
