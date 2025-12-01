require "test_helper"

class UrlFetcherTest < ActiveSupport::TestCase
  test "fetches HTML from valid URL" do
    stub_request(:get, "https://example.com/article")
      .to_return(status: 200, body: "<html><body>Hello</body></html>", headers: { "Content-Type" => "text/html" })

    result = UrlFetcher.call(url: "https://example.com/article")

    assert result.success?
    assert_includes result.html, "Hello"
  end

  test "fails on invalid URL format" do
    result = UrlFetcher.call(url: "not-a-url")

    assert result.failure?
    assert_equal "Invalid URL", result.error
  end

  test "fails on connection timeout" do
    stub_request(:get, "https://example.com/slow")
      .to_timeout

    result = UrlFetcher.call(url: "https://example.com/slow")

    assert result.failure?
    assert_equal "Could not fetch URL", result.error
  end

  test "fails on 404 response" do
    stub_request(:get, "https://example.com/missing")
      .to_return(status: 404)

    result = UrlFetcher.call(url: "https://example.com/missing")

    assert result.failure?
    assert_equal "Could not fetch URL", result.error
  end

  test "fails on 500 response" do
    stub_request(:get, "https://example.com/error")
      .to_return(status: 500)

    result = UrlFetcher.call(url: "https://example.com/error")

    assert result.failure?
    assert_equal "Could not fetch URL", result.error
  end

  test "follows redirects" do
    stub_request(:get, "https://example.com/old")
      .to_return(status: 302, headers: { "Location" => "https://example.com/new" })
    stub_request(:get, "https://example.com/new")
      .to_return(status: 200, body: "<html><body>New page</body></html>")

    result = UrlFetcher.call(url: "https://example.com/old")

    assert result.success?
    assert_includes result.html, "New page"
  end
end
