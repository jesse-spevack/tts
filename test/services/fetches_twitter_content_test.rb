# frozen_string_literal: true

require "test_helper"

class FetchesTwitterContentTest < ActiveSupport::TestCase
  FXTWITTER_BASE = "https://api.fxtwitter.com"
  JINA_BASE = "https://r.jina.ai"
  TWEET_URL = "https://x.com/testuser/status/123456789"

  # --- fxtwitter: X Article ---

  test "extracts X Article content with title and author" do
    body = fxtwitter_article_response(
      author_name: "Test Author",
      screen_name: "testuser",
      blocks: [
        { "type" => "header-one", "text" => "My Article Title" },
        { "type" => "unstyled", "text" => "First paragraph of the article." },
        { "type" => "header-two", "text" => "Section Two" },
        { "type" => "unstyled", "text" => "Second paragraph content." }
      ]
    )

    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_return(status: 200, body: body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert result.success?
    assert_equal "My Article Title", result.data.title
    assert_equal "Test Author (@testuser)", result.data.author
    assert_includes result.data.text, "First paragraph of the article."
    assert_includes result.data.text, "## Section Two"
  end

  test "formats article blocks with markdown headings" do
    body = fxtwitter_article_response(
      blocks: [
        { "type" => "header-one", "text" => "H1 Title" },
        { "type" => "unstyled", "text" => "Paragraph." },
        { "type" => "header-two", "text" => "H2 Section" },
        { "type" => "header-three", "text" => "H3 Subsection" }
      ]
    )

    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_return(status: 200, body: body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert result.success?
    assert_includes result.data.text, "# H1 Title"
    assert_includes result.data.text, "## H2 Section"
    assert_includes result.data.text, "### H3 Subsection"
  end

  # --- fxtwitter: Note Tweet ---

  test "extracts note tweet with full text" do
    body = fxtwitter_text_response(
      text: "This is a long note tweet with more than 280 characters of content that goes on and on.",
      author_name: "Note Author",
      screen_name: "noteuser"
    )

    stub_request(:get, "#{FXTWITTER_BASE}/noteuser/status/123456789")
      .to_return(status: 200, body: body)

    result = FetchesTwitterContent.call(url: "https://x.com/noteuser/status/123456789")

    assert result.success?
    assert_includes result.data.text, "long note tweet"
    assert_equal "Note Author (@noteuser)", result.data.author
    assert_nil result.data.title
  end

  # --- fxtwitter: Regular Tweet ---

  test "extracts regular tweet text" do
    body = fxtwitter_text_response(
      text: "Just a regular tweet.",
      author_name: "Regular User",
      screen_name: "regularuser"
    )

    stub_request(:get, "#{FXTWITTER_BASE}/regularuser/status/123456789")
      .to_return(status: 200, body: body)

    result = FetchesTwitterContent.call(url: "https://x.com/regularuser/status/123456789")

    assert result.success?
    assert_equal "Just a regular tweet.", result.data.text
    assert_equal "Regular User (@regularuser)", result.data.author
  end

  # --- fxtwitter failure -> Jina fallback ---

  test "falls back to Jina when fxtwitter returns HTTP error" do
    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_return(status: 500, body: "Internal Server Error")

    jina_body = jina_json_response(content: "Jina extracted tweet content here")
    stub_request(:get, "#{JINA_BASE}/#{TWEET_URL}")
      .to_return(status: 200, body: jina_body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert result.success?
    assert_includes result.data.text, "Jina extracted tweet content"
    assert_nil result.data.title
    assert_nil result.data.author
  end

  test "falls back to Jina when fxtwitter returns no tweet data" do
    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_return(status: 200, body: { "tweet" => nil }.to_json)

    jina_body = jina_json_response(content: "Jina fallback content")
    stub_request(:get, "#{JINA_BASE}/#{TWEET_URL}")
      .to_return(status: 200, body: jina_body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert result.success?
    assert_includes result.data.text, "Jina fallback content"
  end

  test "falls back to Jina when fxtwitter times out" do
    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_timeout

    jina_body = jina_json_response(content: "Jina timeout fallback")
    stub_request(:get, "#{JINA_BASE}/#{TWEET_URL}")
      .to_return(status: 200, body: jina_body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert result.success?
    assert_includes result.data.text, "Jina timeout fallback"
  end

  test "falls back to Jina when fxtwitter returns malformed JSON" do
    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_return(status: 200, body: "not valid json {{{")

    jina_body = jina_json_response(content: "Jina json fallback")
    stub_request(:get, "#{JINA_BASE}/#{TWEET_URL}")
      .to_return(status: 200, body: jina_body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert result.success?
    assert_includes result.data.text, "Jina json fallback"
  end

  # --- Both fail ---

  test "returns failure when both fxtwitter and Jina fail" do
    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_return(status: 500, body: "Error")

    stub_request(:get, "#{JINA_BASE}/#{TWEET_URL}")
      .to_return(status: 500, body: "Error")

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert result.failure?
    assert_equal "Could not fetch Twitter content", result.error
  end

  # --- Invalid URL ---

  test "returns failure for URL without tweet ID" do
    result = FetchesTwitterContent.call(url: "https://x.com/user")

    assert result.failure?
    assert_equal "Could not fetch Twitter content", result.error
  end

  # --- Author formatting ---

  test "formats author with name and screen_name" do
    body = fxtwitter_text_response(
      text: "Tweet text",
      author_name: "John Doe",
      screen_name: "johndoe"
    )

    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_return(status: 200, body: body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert_equal "John Doe (@johndoe)", result.data.author
  end

  test "formats author with only name" do
    body = fxtwitter_text_response(
      text: "Tweet text",
      author_name: "John Doe",
      screen_name: nil
    )

    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_return(status: 200, body: body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert_equal "John Doe", result.data.author
  end

  test "formats author with only screen_name" do
    body = fxtwitter_text_response(
      text: "Tweet text",
      author_name: nil,
      screen_name: "johndoe"
    )

    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_return(status: 200, body: body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert_equal "@johndoe", result.data.author
  end

  # --- Return type ---

  test "returns ExtractsArticle::ArticleData" do
    body = fxtwitter_text_response(text: "Some tweet content")

    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_return(status: 200, body: body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert result.success?
    assert_kind_of ExtractsArticle::ArticleData, result.data
  end

  test "includes StructuredLogging" do
    assert_includes FetchesTwitterContent.ancestors, StructuredLogging
  end

  test "uses 10 second timeout" do
    service = FetchesTwitterContent.new(url: TWEET_URL)
    connection = service.send(:connection)

    assert_equal 10, connection.options.timeout
    assert_equal 10, connection.options.open_timeout
  end

  # --- fxtwitter connection failure -> Jina fallback ---

  test "falls back to Jina when fxtwitter connection fails" do
    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

    jina_body = jina_json_response(content: "Jina connection fallback")
    stub_request(:get, "#{JINA_BASE}/#{TWEET_URL}")
      .to_return(status: 200, body: jina_body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert result.success?
    assert_includes result.data.text, "Jina connection fallback"
  end

  # --- Article with empty blocks ---

  test "falls back to text when article blocks are empty" do
    body = {
      tweet: {
        text: "Fallback tweet text",
        author: { name: "Author", screen_name: "author" },
        article: { content: { blocks: [] } }
      }
    }.to_json

    stub_request(:get, "#{FXTWITTER_BASE}/testuser/status/123456789")
      .to_return(status: 200, body: body)

    result = FetchesTwitterContent.call(url: TWEET_URL)

    assert result.success?
    assert_equal "Fallback tweet text", result.data.text
  end

  private

  def fxtwitter_article_response(author_name: "Test Author", screen_name: "testuser", blocks: [])
    {
      tweet: {
        text: "Article preview text",
        author: { name: author_name, screen_name: screen_name },
        article: {
          content: {
            blocks: blocks
          }
        }
      }
    }.to_json
  end

  def fxtwitter_text_response(text:, author_name: "Test Author", screen_name: "testuser")
    {
      tweet: {
        text: text,
        author: { name: author_name, screen_name: screen_name }
      }
    }.to_json
  end

  def jina_json_response(content:)
    {
      code: 200,
      status: 20000,
      data: {
        title: "Test Article",
        description: "A test article",
        url: TWEET_URL,
        content: content
      }
    }.to_json
  end
end
