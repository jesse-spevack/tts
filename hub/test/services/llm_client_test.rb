# frozen_string_literal: true

require "test_helper"
require "ostruct"

class LlmClientTest < ActiveSupport::TestCase
  setup do
    Mocktail.replace(RubyLLM)
  end

  test "ask sends prompt to RubyLLM chat with provider" do
    mock_response = OpenStruct.new(content: "response", input_tokens: 10, output_tokens: 5)
    mock_chat = Object.new
    mock_chat.define_singleton_method(:with_params) { |**_params| self }
    mock_chat.define_singleton_method(:ask) { |_prompt| mock_response }

    stubs { RubyLLM.chat(model: LlmClient::DEFAULT_MODEL, provider: LlmClient::PROVIDER) }.with { mock_chat }

    client = LlmClient.new
    result = client.ask("test prompt")

    assert_equal "response", result.content
  end

  test "ask uses custom model when provided" do
    custom_model = "gemini-1.5-flash"
    mock_response = OpenStruct.new(content: "response")
    mock_chat = Object.new
    mock_chat.define_singleton_method(:with_params) { |**_params| self }
    mock_chat.define_singleton_method(:ask) { |_prompt| mock_response }

    stubs { RubyLLM.chat(model: custom_model, provider: LlmClient::PROVIDER) }.with { mock_chat }

    client = LlmClient.new(model: custom_model)
    result = client.ask("test prompt")

    assert_equal "response", result.content
  end

  test "find_model delegates to RubyLLM models registry" do
    mock_model_info = OpenStruct.new(input_price_per_million: 0.25, output_price_per_million: 1.25)
    mock_registry = Object.new
    mock_registry.define_singleton_method(:find) { |_model_id| mock_model_info }

    stubs { RubyLLM.models }.with { mock_registry }

    client = LlmClient.new
    result = client.find_model("gemini-2.0-flash")

    assert_equal 0.25, result.input_price_per_million
    assert_equal 1.25, result.output_price_per_million
  end
end
