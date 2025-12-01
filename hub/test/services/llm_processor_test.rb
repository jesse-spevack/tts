# frozen_string_literal: true

require "test_helper"
require "ostruct"

class LlmProcessorTest < ActiveSupport::TestCase
  setup do
    @episode = episodes(:one)
    @text = "This is some article content about technology trends."
    @user = users(:one)

    Mocktail.replace(LlmClient)
    Mocktail.replace(RecordLlmUsage)
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

    stub_llm_client(mock_response)
    stub_record_usage

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.success?
    assert_equal "Technology Trends", result.title
    assert_equal "Unknown", result.author
    assert_includes result.description, "technology"
    assert_includes result.content, "article content"
  end

  test "fails on LLM error" do
    mock_client = Mocktail.of(LlmClient)
    stubs { |m| mock_client.ask(m.any) }.with { raise RubyLLM::Error.new("API error", response: nil) }
    stubs { LlmClient.new }.with { mock_client }

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.failure?
    assert_equal "Failed to process content", result.error
  end

  test "fails on invalid JSON response" do
    mock_response = mock_llm_response(content: "not valid json")
    stub_llm_client(mock_response)

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.failure?
    assert_equal "Failed to process content", result.error
  end

  test "strips markdown code blocks from response" do
    json_with_markdown = "```json\n{\"title\": \"Test\", \"author\": \"A\", \"description\": \"D\", \"content\": \"C\"}\n```"
    mock_response = mock_llm_response(content: json_with_markdown)

    stub_llm_client(mock_response)
    stub_record_usage

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.success?
    assert_equal "Test", result.title
  end

  # Validation tests

  test "fails when content is missing from response" do
    mock_response = mock_llm_response(
      content: { title: "Test", author: "A", description: "D" }.to_json
    )
    stub_llm_client(mock_response)

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.failure?
    assert_equal "Failed to process content", result.error
  end

  test "fails when content is empty string" do
    mock_response = mock_llm_response(
      content: { title: "Test", author: "A", description: "D", content: "" }.to_json
    )
    stub_llm_client(mock_response)

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.failure?
    assert_equal "Failed to process content", result.error
  end

  test "uses default title when missing" do
    mock_response = mock_llm_response(
      content: { author: "A", description: "D", content: "Some content" }.to_json
    )
    stub_llm_client(mock_response)
    stub_record_usage

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.success?
    assert_equal "Untitled", result.title
  end

  test "uses default author when missing" do
    mock_response = mock_llm_response(
      content: { title: "T", description: "D", content: "Some content" }.to_json
    )
    stub_llm_client(mock_response)
    stub_record_usage

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.success?
    assert_equal "Unknown", result.author
  end

  test "truncates long title" do
    long_title = "A" * 300
    mock_response = mock_llm_response(
      content: { title: long_title, author: "A", description: "D", content: "C" }.to_json
    )
    stub_llm_client(mock_response)
    stub_record_usage

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.success?
    assert_equal 255, result.title.length
    assert result.title.end_with?("...")
  end

  test "handles non-string values gracefully" do
    mock_response = mock_llm_response(
      content: { title: 123, author: nil, description: [ "array" ], content: "Valid content" }.to_json
    )
    stub_llm_client(mock_response)
    stub_record_usage

    result = LlmProcessor.call(text: @text, episode: @episode, user: @user)

    assert result.success?
    assert_equal "Untitled", result.title
    assert_equal "Unknown", result.author
    assert_equal "", result.description
    assert_equal "Valid content", result.content
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

  def stub_llm_client(response)
    mock_client = Mocktail.of(LlmClient)
    stubs { |m| mock_client.ask(m.any) }.with { response }
    stubs { LlmClient.new }.with { mock_client }
  end

  def stub_record_usage
    stubs { |m| RecordLlmUsage.call(episode: m.any, response: m.any) }.with { LlmUsage.new }
  end
end
