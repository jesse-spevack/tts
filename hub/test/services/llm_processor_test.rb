require "test_helper"
require "ostruct"

class LlmProcessorTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @text = "This is some article content about technology trends."
    @user = users(:one)
  end

  test "processes text and returns structured result" do
    mock_response = OpenStruct.new(
      content: {
        title: "Technology Trends",
        author: "Unknown",
        description: "An article about technology trends.",
        content: "This is some article content about technology trends."
      }.to_json,
      input_tokens: 100,
      output_tokens: 50,
      model_id: "claude-3-haiku-20240307"
    )

    mock_chat = MockChat.new(mock_response)
    mock_models = MockModels.new

    result = LlmProcessor.call(
      text: @text,
      episode: @episode,
      user: @user,
      chat_client: mock_chat,
      models_registry: mock_models
    )

    assert result.success?
    assert_equal "Technology Trends", result.title
    assert_equal "Unknown", result.author
    assert_includes result.description, "technology"
    assert_includes result.content, "article content"
  end

  test "creates LlmUsage record" do
    mock_response = OpenStruct.new(
      content: {
        title: "Test",
        author: "Author",
        description: "Description",
        content: "Content"
      }.to_json,
      input_tokens: 100,
      output_tokens: 50,
      model_id: "claude-3-haiku-20240307"
    )

    mock_chat = MockChat.new(mock_response)
    mock_models = MockModels.new

    assert_difference -> { LlmUsage.count }, 1 do
      LlmProcessor.call(
        text: @text,
        episode: @episode,
        user: @user,
        chat_client: mock_chat,
        models_registry: mock_models
      )
    end

    usage = LlmUsage.last
    assert_equal @episode, usage.episode
    assert_equal "claude-3-haiku-20240307", usage.model_id
    assert_equal "vertex_ai", usage.provider
    assert_equal 100, usage.input_tokens
    assert_equal 50, usage.output_tokens
  end

  test "fails on LLM error" do
    mock_chat = MockChatWithError.new

    result = LlmProcessor.call(
      text: @text,
      episode: @episode,
      user: @user,
      chat_client: mock_chat
    )

    assert result.failure?
    assert_equal "Failed to process content", result.error
  end

  test "fails on invalid JSON response" do
    mock_response = OpenStruct.new(
      content: "not valid json",
      input_tokens: 100,
      output_tokens: 50,
      model_id: "claude-3-haiku-20240307"
    )

    mock_chat = MockChat.new(mock_response)

    result = LlmProcessor.call(
      text: @text,
      episode: @episode,
      user: @user,
      chat_client: mock_chat
    )

    assert result.failure?
    assert_equal "Failed to process content", result.error
  end

  class MockChat
    def initialize(response)
      @response = response
    end

    def ask(_prompt)
      @response
    end
  end

  class MockLlmError < RubyLLM::Error
    def initialize(message)
      @message = message
    end

    def message
      @message
    end
  end

  class MockChatWithError
    def ask(_prompt)
      raise MockLlmError.new("API error")
    end
  end

  class MockModels
    def find(_model_id)
      OpenStruct.new(
        input_price_per_million: 0.25,
        output_price_per_million: 1.25
      )
    end
  end
end
