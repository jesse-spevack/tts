require "test_helper"

class FetchesUrlTest < ActiveSupport::TestCase
  include Mocktail::DSL

  teardown do
    Mocktail.reset
  end

  test "fetches HTML from valid URL" do
    stub_request(:head, "https://example.com/article")
      .to_return(status: 200, headers: { "Content-Length" => "100" })
    stub_request(:get, "https://example.com/article")
      .to_return(status: 200, body: "<html><body>Hello</body></html>", headers: { "Content-Type" => "text/html" })

    result = FetchesUrl.call(url: "https://example.com/article")

    assert result.success?
    assert_includes result.data, "Hello"
  end

  test "fails on invalid URL format" do
    result = FetchesUrl.call(url: "not-a-url")

    assert result.failure?
    assert_equal "Invalid URL", result.error
  end

  test "fails on connection timeout" do
    stub_request(:head, "https://example.com/slow")
      .to_timeout

    result = FetchesUrl.call(url: "https://example.com/slow")

    assert result.failure?
    assert_equal "Could not fetch URL", result.error
  end

  test "fails on 404 response" do
    stub_request(:head, "https://example.com/missing")
      .to_return(status: 200)
    stub_request(:get, "https://example.com/missing")
      .to_return(status: 404)

    result = FetchesUrl.call(url: "https://example.com/missing")

    assert result.failure?
    assert_equal "Could not fetch URL", result.error
  end

  test "fails on 500 response" do
    stub_request(:head, "https://example.com/error")
      .to_return(status: 200)
    stub_request(:get, "https://example.com/error")
      .to_return(status: 500)

    result = FetchesUrl.call(url: "https://example.com/error")

    assert result.failure?
    assert_equal "Could not fetch URL", result.error
  end

  test "follows redirects" do
    stub_request(:head, "https://example.com/old")
      .to_return(status: 302, headers: { "Location" => "https://example.com/new" })
    stub_request(:head, "https://example.com/new")
      .to_return(status: 200)
    stub_request(:get, "https://example.com/old")
      .to_return(status: 302, headers: { "Location" => "https://example.com/new" })
    stub_request(:get, "https://example.com/new")
      .to_return(status: 200, body: "<html><body>New page</body></html>")

    result = FetchesUrl.call(url: "https://example.com/old")

    assert result.success?
    assert_includes result.data, "New page"
  end

  test "rejects content exceeding max size based on Content-Length header" do
    stub_request(:head, "https://example.com/large")
      .to_return(status: 200, headers: { "Content-Length" => "20000000" })

    result = FetchesUrl.call(url: "https://example.com/large")

    assert result.failure?
    assert_equal "Content too large", result.error
  end

  test "blocks redirect to localhost (DNS rebinding protection)" do
    fetcher = FetchesUrl.new(url: "https://example.com")

    # Simulate redirect to localhost
    new_env = { url: URI.parse("http://localhost/secret") }

    assert_raises(Faraday::ConnectionFailed) do
      fetcher.send(:validate_redirect_target, {}, new_env)
    end
  end

  test "blocks redirect to private IP" do
    fetcher = FetchesUrl.new(url: "https://example.com")

    new_env = { url: URI.parse("http://192.168.1.1/admin") }

    assert_raises(Faraday::ConnectionFailed) do
      fetcher.send(:validate_redirect_target, {}, new_env)
    end
  end

  test "blocks redirect to cloud metadata endpoint" do
    fetcher = FetchesUrl.new(url: "https://example.com")

    new_env = { url: URI.parse("http://169.254.169.254/latest/meta-data/") }

    assert_raises(Faraday::ConnectionFailed) do
      fetcher.send(:validate_redirect_target, {}, new_env)
    end
  end

  # SSRF protection tests - test blocked_ip? method directly

  test "blocked_ip? returns true for localhost" do
    fetcher = FetchesUrl.new(url: "http://example.com")
    assert fetcher.send(:blocked_ip?, "127.0.0.1")
    assert fetcher.send(:blocked_ip?, "127.0.0.255")
  end

  test "blocked_ip? returns true for private 10.x.x.x" do
    fetcher = FetchesUrl.new(url: "http://example.com")
    assert fetcher.send(:blocked_ip?, "10.0.0.1")
    assert fetcher.send(:blocked_ip?, "10.255.255.255")
  end

  test "blocked_ip? returns true for private 172.16.x.x" do
    fetcher = FetchesUrl.new(url: "http://example.com")
    assert fetcher.send(:blocked_ip?, "172.16.0.1")
    assert fetcher.send(:blocked_ip?, "172.31.255.255")
  end

  test "blocked_ip? returns true for private 192.168.x.x" do
    fetcher = FetchesUrl.new(url: "http://example.com")
    assert fetcher.send(:blocked_ip?, "192.168.0.1")
    assert fetcher.send(:blocked_ip?, "192.168.255.255")
  end

  test "blocked_ip? returns true for cloud metadata 169.254.x.x" do
    fetcher = FetchesUrl.new(url: "http://example.com")
    assert fetcher.send(:blocked_ip?, "169.254.169.254")
  end

  test "blocked_ip? returns true for IPv6 loopback" do
    fetcher = FetchesUrl.new(url: "http://example.com")
    assert fetcher.send(:blocked_ip?, "::1")
  end

  test "blocked_ip? returns true for IPv6 private" do
    fetcher = FetchesUrl.new(url: "http://example.com")
    assert fetcher.send(:blocked_ip?, "fc00::1")
    assert fetcher.send(:blocked_ip?, "fd00::1")
  end

  test "blocked_ip? returns false for public IPs" do
    fetcher = FetchesUrl.new(url: "http://example.com")
    assert_not fetcher.send(:blocked_ip?, "93.184.216.34")
    assert_not fetcher.send(:blocked_ip?, "8.8.8.8")
    assert_not fetcher.send(:blocked_ip?, "1.1.1.1")
  end

  test "blocked_ip? returns true for invalid IP" do
    fetcher = FetchesUrl.new(url: "http://example.com")
    assert fetcher.send(:blocked_ip?, "not-an-ip")
  end

  test "safe_host? integration with actual localhost" do
    fetcher = FetchesUrl.new(url: "http://localhost/admin")
    assert_not fetcher.send(:safe_host?)
  end

  test "safe_host? integration with 127.0.0.1" do
    fetcher = FetchesUrl.new(url: "http://127.0.0.1/admin")
    assert_not fetcher.send(:safe_host?)
  end

  test "blocks localhost URL via call" do
    result = FetchesUrl.call(url: "http://localhost/admin")
    assert result.failure?
    assert_equal "URL not allowed", result.error
  end

  test "blocks 127.0.0.1 URL via call" do
    result = FetchesUrl.call(url: "http://127.0.0.1/secret")
    assert result.failure?
    assert_equal "URL not allowed", result.error
  end
end
