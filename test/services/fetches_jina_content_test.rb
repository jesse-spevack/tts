# frozen_string_literal: true

require "test_helper"

class FetchesJinaContentTest < ActiveSupport::TestCase
  JINA_BASE = "https://r.jina.ai"
  TARGET_URL = "https://stripe.dev/blog/minions"

  test "returns success with content extracted from JSON response" do
    body = jina_json_response(content: "# Minions\n\nStripe's one-shot coding agents...")

    stub_request(:get, "#{JINA_BASE}/#{TARGET_URL}")
      .to_return(status: 200, body: body)

    result = FetchesJinaContent.call(url: TARGET_URL)

    assert result.success?
    assert_includes result.data, "Minions"
  end

  test "sends Accept application/json header" do
    body = jina_json_response(content: "some content")

    stub_request(:get, "#{JINA_BASE}/#{TARGET_URL}")
      .with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: body)

    result = FetchesJinaContent.call(url: TARGET_URL)

    assert result.success?
  end

  test "returns failure on timeout" do
    stub_request(:get, "#{JINA_BASE}/#{TARGET_URL}")
      .to_timeout

    result = FetchesJinaContent.call(url: TARGET_URL)

    assert result.failure?
    assert_equal "Could not fetch content from reader service", result.error
  end

  test "returns failure on HTTP error response" do
    stub_request(:get, "#{JINA_BASE}/#{TARGET_URL}")
      .to_return(status: 500, body: "Internal Server Error")

    result = FetchesJinaContent.call(url: TARGET_URL)

    assert result.failure?
    assert_equal "Could not fetch content from reader service", result.error
  end

  test "returns failure on 404 response" do
    stub_request(:get, "#{JINA_BASE}/#{TARGET_URL}")
      .to_return(status: 404, body: "Not Found")

    result = FetchesJinaContent.call(url: TARGET_URL)

    assert result.failure?
    assert_equal "Could not fetch content from reader service", result.error
  end

  test "returns failure on connection error" do
    stub_request(:get, "#{JINA_BASE}/#{TARGET_URL}")
      .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

    result = FetchesJinaContent.call(url: TARGET_URL)

    assert result.failure?
    assert_equal "Could not fetch content from reader service", result.error
  end

  test "uses 10 second timeout" do
    service = FetchesJinaContent.new(url: TARGET_URL)
    connection = service.send(:connection)

    assert_equal 10, connection.options.timeout
    assert_equal 10, connection.options.open_timeout
  end

  test "includes StructuredLogging" do
    assert_includes FetchesJinaContent.ancestors, StructuredLogging
  end

  test "constructs Jina URL from target URL" do
    body = jina_json_response(content: "Page content here")

    stub_request(:get, "#{JINA_BASE}/https://example.com/page")
      .to_return(status: 200, body: body)

    result = FetchesJinaContent.call(url: "https://example.com/page")

    assert result.success?
    assert_equal "Page content here", result.data
  end

  # Finding 6: Handle malformed JSON response
  test "returns failure on malformed JSON response" do
    stub_request(:get, "#{JINA_BASE}/#{TARGET_URL}")
      .to_return(status: 200, body: "not valid json at all {{{")

    result = FetchesJinaContent.call(url: TARGET_URL)

    assert result.failure?
    assert_equal "Could not fetch content from reader service", result.error
  end

  # Finding 3: Guard against empty response body
  test "returns failure when JSON content field is blank" do
    body = jina_json_response(content: "")

    stub_request(:get, "#{JINA_BASE}/#{TARGET_URL}")
      .to_return(status: 200, body: body)

    result = FetchesJinaContent.call(url: TARGET_URL)

    assert result.failure?
    assert_equal "Could not fetch content from reader service", result.error
  end

  test "returns failure when JSON content field is nil" do
    body = { code: 200, status: 20000, data: { title: "Test", content: nil } }.to_json

    stub_request(:get, "#{JINA_BASE}/#{TARGET_URL}")
      .to_return(status: 200, body: body)

    result = FetchesJinaContent.call(url: TARGET_URL)

    assert result.failure?
    assert_equal "Could not fetch content from reader service", result.error
  end

  # Finding 5: Add response size limit
  test "returns failure when response body exceeds MAX_FETCH_BYTES" do
    oversized_content = "x" * (AppConfig::Content::MAX_FETCH_BYTES + 1)

    stub_request(:get, "#{JINA_BASE}/#{TARGET_URL}")
      .to_return(status: 200, body: oversized_content)

    result = FetchesJinaContent.call(url: TARGET_URL)

    assert result.failure?
    assert_equal "Could not fetch content from reader service", result.error
  end

  private

  def jina_json_response(content:)
    {
      code: 200,
      status: 20000,
      data: {
        title: "Test Article",
        description: "A test article",
        url: TARGET_URL,
        content: content
      }
    }.to_json
  end
end
