require "test_helper"
require "ostruct"

class LlmProcessorTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @text = "This is some article content about technology trends."
    @user = users(:one)

    Mocktail.replace(RubyLLM)
  end

  test "processes text and returns structured result" do
    mock_response = mock_llm_response(
      content: {
        title: "Technology Trends",
        author: "Unknown",
        description: "An article about technology trends.",
        content: "This is some article content about technology trends."
      }.to_json
    )
    mock_chat = mock_chat_client(mock_response)

    stubs { RubyLLM.chat(model: LlmProcessor::MODEL) }.with { mock_chat }
    stubs { RubyLLM.models }.with { mock_models_registry }

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.success?
    assert_equal "Technology Trends", result.title
    assert_equal "Unknown", result.author
    assert_includes result.description, "technology"
    assert_includes result.content, "article content"
  end

  test "creates LlmUsage record" do
    mock_response = mock_llm_response(
      content: { title: "Test", author: "Author", description: "Description", content: "Content" }.to_json
    )
    mock_chat = mock_chat_client(mock_response)

    stubs { RubyLLM.chat(model: LlmProcessor::MODEL) }.with { mock_chat }
    stubs { RubyLLM.models }.with { mock_models_registry }

    assert_difference -> { LlmUsage.count }, 1 do
      LlmProcessor.call(text: @text, episode: @episode, user: @user)
    end

    usage = LlmUsage.last
    assert_equal @episode, usage.episode
    assert_equal "claude-3-haiku-20240307", usage.model_id
    assert_equal "vertex_ai", usage.provider
    assert_equal 100, usage.input_tokens
    assert_equal 50, usage.output_tokens
  end

  test "fails on LLM error" do
    mock_chat = Object.new
    mock_chat.define_singleton_method(:ask) { |_| raise RubyLLM::Error.new("API error", response: nil) }

    stubs { RubyLLM.chat(model: LlmProcessor::MODEL) }.with { mock_chat }

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.failure?
    assert_equal "Failed to process content", result.error
  end

  test "fails on invalid JSON response" do
    mock_response = mock_llm_response(content: "not valid json")
    mock_chat = mock_chat_client(mock_response)

    stubs { RubyLLM.chat(model: LlmProcessor::MODEL) }.with { mock_chat }

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.failure?
    assert_equal "Failed to process content", result.error
  end

  private

  def mock_llm_response(content:, input_tokens: 100, output_tokens: 50, model_id: "claude-3-haiku-20240307")
    OpenStruct.new(
      content: content,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      model_id: model_id
    )
  end

  def mock_chat_client(response)
    chat = Object.new
    chat.define_singleton_method(:ask) { |_| response }
    chat
  end

  def mock_models_registry
    registry = Object.new
    registry.define_singleton_method(:find) do |_model_id|
      OpenStruct.new(
        input_price_per_million: 0.25,
        output_price_per_million: 1.25
      )
    end
    registry
  end
end
