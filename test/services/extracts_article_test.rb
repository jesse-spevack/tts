require "test_helper"

class ExtractsArticleTest < ActiveSupport::TestCase
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

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_includes result.data.text, "Article Title"
    assert_includes result.data.text, "main content"
    assert_not_includes result.data.text, "Navigation"
    assert_not_includes result.data.text, "Footer content"
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

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_includes result.data.text, "Main Content"
    assert_includes result.data.text, "Body text"
    assert_not_includes result.data.text, "Nav"
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

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_includes result.data.text, "Page Content"
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

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_includes result.data.text, "Real content"
    assert_not_includes result.data.text, "alert"
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

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_not_includes result.data.text, "color"
  end

  test "fails when no content found" do
    html = "<html><body></body></html>"

    result = ExtractsArticle.call(html: html)

    assert result.failure?
    assert_equal "Could not extract article content", result.error
  end

  test "returns character count" do
    html = "<article><p>Hello world with enough content to pass the minimum length requirement. This paragraph contains sufficient characters for the extraction to succeed and return a positive character count.</p></article>"

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert result.data.character_count.positive?
  end

  test "fails when HTML exceeds size limit" do
    # Create HTML larger than 10MB
    large_content = "x" * (11 * 1024 * 1024)
    html = "<article><p>#{large_content}</p></article>"

    result = ExtractsArticle.call(html: html)

    assert result.failure?
    assert_equal "Article content too large", result.error
  end

  test "accepts HTML at size limit" do
    # Create HTML just under 10MB with valid content
    padding = "y" * 200
    html = "<article><p>Valid content with enough text. #{padding}</p></article>"

    result = ExtractsArticle.call(html: html)

    assert result.success?
  end

  test "extracts title from title tag" do
    html = <<~HTML
      <html>
        <head><title>My Article Title</title></head>
        <body>
          <article>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "My Article Title", result.data.title
  end

  test "extracts author from meta tag" do
    html = <<~HTML
      <html>
        <head>
          <title>Article</title>
          <meta name="author" content="Jane Smith">
        </head>
        <body>
          <article>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "Jane Smith", result.data.author
  end

  test "returns nil for missing metadata" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_nil result.data.title
    assert_nil result.data.author
  end

  # --- Expanded author extraction tests ---

  test "extracts author from article:author meta property" do
    html = <<~HTML
      <html>
        <head>
          <meta property="article:author" content="Alice Walker">
        </head>
        <body>
          <article>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "Alice Walker", result.data.author
  end

  test "extracts author from og:article:author meta property" do
    html = <<~HTML
      <html>
        <head>
          <meta property="og:article:author" content="Bob Marley">
        </head>
        <body>
          <article>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "Bob Marley", result.data.author
  end

  test "extracts author from twitter:creator meta tag" do
    html = <<~HTML
      <html>
        <head>
          <meta name="twitter:creator" content="Carol Danvers">
        </head>
        <body>
          <article>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "Carol Danvers", result.data.author
  end

  test "extracts author from rel=author element" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <a rel="author">David Foster Wallace</a>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "David Foster Wallace", result.data.author
  end

  test "extracts author from byline class element" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <span class="byline">Eleanor Roosevelt</span>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "Eleanor Roosevelt", result.data.author
  end

  test "extracts author from author class element" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <span class="author">Frank Herbert</span>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "Frank Herbert", result.data.author
  end

  test "meta name=author takes priority over article:author" do
    html = <<~HTML
      <html>
        <head>
          <meta name="author" content="Primary Author">
          <meta property="article:author" content="Secondary Author">
        </head>
        <body>
          <article>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "Primary Author", result.data.author
  end

  test "article:author takes priority over og:article:author" do
    html = <<~HTML
      <html>
        <head>
          <meta property="article:author" content="Article Author">
          <meta property="og:article:author" content="OG Author">
        </head>
        <body>
          <article>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "Article Author", result.data.author
  end

  test "meta tags take priority over byline selectors" do
    html = <<~HTML
      <html>
        <head>
          <meta property="article:author" content="Meta Author">
        </head>
        <body>
          <article>
            <span class="byline">Byline Author</span>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "Meta Author", result.data.author
  end

  test "byline selectors work when no meta tags exist" do
    html = <<~HTML
      <html>
        <body>
          <article>
            <div class="byline">Sean Goedecke</div>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "Sean Goedecke", result.data.author
  end

  test "strips whitespace from extracted author in all selectors" do
    html = <<~HTML
      <html>
        <head>
          <meta property="article:author" content="  Whitespace Author  ">
        </head>
        <body>
          <article>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_equal "Whitespace Author", result.data.author
  end

  test "returns nil when author meta tags and byline selectors are all empty" do
    html = <<~HTML
      <html>
        <head>
          <meta property="article:author" content="">
          <meta property="og:article:author" content="">
        </head>
        <body>
          <article>
            <span class="byline"></span>
            <p>Content that is long enough to pass the minimum length requirement for extraction. This paragraph needs substantial content.</p>
          </article>
        </body>
      </html>
    HTML

    result = ExtractsArticle.call(html: html)

    assert result.success?
    assert_nil result.data.author
  end
end
