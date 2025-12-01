require "test_helper"

class ArticleExtractorTest < ActiveSupport::TestCase
  test "extracts article content from simple HTML" do
    html = <<~HTML
      <html>
        <head><title>Page Title</title></head>
        <body>
          <nav>Navigation</nav>
          <article>
            <h1>Article Title</h1>
            <p>This is the main content of the article. It contains enough text to pass the minimum length requirement for extraction. The article discusses important topics.</p>
            <p>More content here with additional paragraphs to ensure we have sufficient text for the extraction to succeed properly.</p>
          </article>
          <footer>Footer content</footer>
        </body>
      </html>
    HTML

    result = ArticleExtractor.call(html: html)

    assert result.success?
    assert_includes result.text, "Article Title"
    assert_includes result.text, "main content"
    assert_not_includes result.text, "Navigation"
    assert_not_includes result.text, "Footer content"
  end

  test "extracts from main tag if no article" do
    html = <<~HTML
      <html>
        <body>
          <nav>Nav</nav>
          <main>
            <h1>Main Content</h1>
            <p>Body text here with enough content to pass the minimum length requirement. This paragraph contains important information about the topic at hand and provides valuable insights.</p>
          </main>
        </body>
      </html>
    HTML

    result = ArticleExtractor.call(html: html)

    assert result.success?
    assert_includes result.text, "Main Content"
    assert_includes result.text, "Body text"
    assert_not_includes result.text, "Nav"
  end

  test "falls back to body if no article or main" do
    html = <<~HTML
      <html>
        <body>
          <div class="content">
            <h1>Page Content</h1>
            <p>Some text that provides enough content to meet the minimum length requirement for extraction. This body fallback test needs sufficient characters to pass validation.</p>
          </div>
        </body>
      </html>
    HTML

    result = ArticleExtractor.call(html: html)

    assert result.success?
    assert_includes result.text, "Page Content"
  end

  test "removes script tags" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <p>Real content that provides enough text for the minimum length requirement. This article has substantial content that should be extracted without the script tags being included in the output.</p>
            <script>alert('bad');</script>
          </article>
        </body>
      </html>
    HTML

    result = ArticleExtractor.call(html: html)

    assert result.success?
    assert_includes result.text, "Real content"
    assert_not_includes result.text, "alert"
  end

  test "removes style tags" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <p>Real content that provides enough text for the minimum length requirement. This article has substantial content that should be extracted without the style tags being included in the output.</p>
            <style>.foo { color: red; }</style>
          </article>
        </body>
      </html>
    HTML

    result = ArticleExtractor.call(html: html)

    assert result.success?
    assert_not_includes result.text, "color"
  end

  test "fails when no content found" do
    html = "<html><body></body></html>"

    result = ArticleExtractor.call(html: html)

    assert result.failure?
    assert_equal "Could not extract article content", result.error
  end

  test "returns character count" do
    html = "<article><p>Hello world with enough content to pass the minimum length requirement. This paragraph contains sufficient characters for the extraction to succeed and return a positive character count.</p></article>"

    result = ArticleExtractor.call(html: html)

    assert result.success?
    assert result.character_count.positive?
  end

  test "fails when HTML exceeds size limit" do
    # Create HTML larger than 10MB
    large_content = "x" * (11 * 1024 * 1024)
    html = "<article><p>#{large_content}</p></article>"

    result = ArticleExtractor.call(html: html)

    assert result.failure?
    assert_equal "Article content too large", result.error
  end

  test "accepts HTML at size limit" do
    # Create HTML just under 10MB with valid content
    padding = "y" * 200
    html = "<article><p>Valid content with enough text. #{padding}</p></article>"

    result = ArticleExtractor.call(html: html)

    assert result.success?
  end
end
