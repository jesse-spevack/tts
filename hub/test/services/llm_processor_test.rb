# frozen_string_literal: true

require "test_helper"
require "ostruct"

class LlmProcessorTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @text = "This is some article content about technology trends."
    @user = users(:one)
  end

  test "processes text and returns structured result" do
    mock_client = mock_llm_client(
      content: {
        title: "Technology Trends",
        author: "Unknown",
        description: "An article about technology trends.",
        content: "This is some article content about technology trends."
      }.to_json
    )

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user, llm_client: mock_client)

    assert result.success?
    assert_equal "Technology Trends", result.title
    assert_equal "Unknown", result.author
    assert_includes result.description, "technology"
    assert_includes result.content, "article content"
  end

  test "creates LlmUsage record" do
    mock_client = mock_llm_client(
      content: { title: "Test", author: "Author", description: "Description", content: "Content" }.to_json
    )

    assert_difference -> { LlmUsage.count }, 1 do
      LlmProcessor.call(text: @text, episode: @episode, user: @user, llm_client: mock_client)
    end

    usage = LlmUsage.last
    assert_equal @episode, usage.episode
    assert_equal "claude-3-haiku-20240307", usage.model_id
    assert_equal "vertex_ai", usage.provider
    assert_equal 100, usage.input_tokens
    assert_equal 50, usage.output_tokens
  end

  test "fails on LLM error" do
    mock_client = Object.new
    mock_client.define_singleton_method(:ask) { |_| raise RubyLLM::Error.new("API error", response: nil) }

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user, llm_client: mock_client)

    assert result.failure?
    assert_equal "Failed to process content", result.error
  end

  test "fails on invalid JSON response" do
    mock_client = mock_llm_client(content: "not valid json")

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user, llm_client: mock_client)

    assert result.failure?
    assert_equal "Failed to process content", result.error
  end

  test "strips markdown code blocks from response" do
    json_with_markdown = "```json\n{\"title\": \"Test\", \"author\": \"A\", \"description\": \"D\", \"content\": \"C\"}\n```"
    mock_client = mock_llm_client(content: json_with_markdown)

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user, llm_client: mock_client)

    assert result.success?
    assert_equal "Test", result.title
  end

  private

  def mock_llm_client(content:, input_tokens: 100, output_tokens: 50, model_id: "claude-3-haiku-20240307")
    response = OpenStruct.new(
      content: content,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      model_id: model_id
    )

    model_info = OpenStruct.new(
      input_price_per_million: 0.25,
      output_price_per_million: 1.25
    )

    client = Object.new
    client.define_singleton_method(:ask) { |_prompt| response }
    client.define_singleton_method(:find_model) { |_model_id| model_info }
    client
  end
end
