require "test_helper"

class FetchesUrlTest < ActiveSupport::TestCase
  include Mocktail::DSL

  # Use a real public IP for example.com to pass SSRF checks
  EXAMPLE_COM_IP = "93.184.216.34"

  teardown do
    Mocktail.reset
  end

  # Helper to stub DNS resolution
  def with_dns_stub(addresses)
    original_method = Resolv.method(:getaddresses)
    Resolv.define_singleton_method(:getaddresses) { |_host| addresses }
    yield
  ensure
    Resolv.define_singleton_method(:getaddresses, original_method)
  end

  test "fetches HTML from valid URL" do
    stub_request(:head, "https://example.com/article")
      .to_return(status: 200, headers: { "Content-Length" => "100" })
    stub_request(:get, "https://example.com/article")
      .to_return(status: 200, body: "<html><body>Hello</body></html>", headers: { "Content-Type" => "text/html" })

    with_dns_stub([ EXAMPLE_COM_IP ]) do
      result = FetchesUrl.call(url: "https://example.com/article")

      assert result.success?
      assert_includes result.data, "Hello"
    end
  end

  test "fails on invalid URL format" do
    result = FetchesUrl.call(url: "not-a-url")

    assert result.failure?
    assert_equal "Invalid URL", result.error
  end

  test "fails on connection timeout" do
    stub_request(:head, "https://example.com/slow")
      .to_timeout

    with_dns_stub([ EXAMPLE_COM_IP ]) do
      result = FetchesUrl.call(url: "https://example.com/slow")

      assert result.failure?
      assert_equal "Could not fetch URL", result.error
    end
  end

  test "fails on 404 response" do
    stub_request(:head, "https://example.com/missing")
      .to_return(status: 200)
    stub_request(:get, "https://example.com/missing")
      .to_return(status: 404)

    with_dns_stub([ EXAMPLE_COM_IP ]) do
      result = FetchesUrl.call(url: "https://example.com/missing")

      assert result.failure?
      assert_equal "Could not fetch URL", result.error
    end
  end

  test "fails on 500 response" do
    stub_request(:head, "https://example.com/error")
      .to_return(status: 200)
    stub_request(:get, "https://example.com/error")
      .to_return(status: 500)

    with_dns_stub([ EXAMPLE_COM_IP ]) do
      result = FetchesUrl.call(url: "https://example.com/error")

      assert result.failure?
      assert_equal "Could not fetch URL", result.error
    end
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

    with_dns_stub([ EXAMPLE_COM_IP ]) do
      result = FetchesUrl.call(url: "https://example.com/old")

      assert result.success?
      assert_includes result.data, "New page"
    end
  end

  test "rejects content exceeding max size based on Content-Length header" do
    stub_request(:head, "https://example.com/large")
      .to_return(status: 200, headers: { "Content-Length" => "20000000" })

    with_dns_stub([ EXAMPLE_COM_IP ]) do
      result = FetchesUrl.call(url: "https://example.com/large")

      assert result.failure?
      assert_equal "Content too large", result.error
    end
  end

  test "blocks redirect to localhost (DNS rebinding protection)" do
    fetcher = FetchesUrl.new(url: "https://example.com")

    # Simulate redirect to localhost - stub DNS to return localhost IP
    new_env = { url: URI.parse("http://localhost/secret") }

    with_dns_stub([ "127.0.0.1" ]) do
      assert_raises(Faraday::ConnectionFailed) do
        fetcher.send(:validate_redirect_target, {}, new_env)
      end
    end
  end

  test "blocks redirect to private IP" do
    fetcher = FetchesUrl.new(url: "https://example.com")

    new_env = { url: URI.parse("http://192.168.1.1/admin") }

    with_dns_stub([ "192.168.1.1" ]) do
      assert_raises(Faraday::ConnectionFailed) do
        fetcher.send(:validate_redirect_target, {}, new_env)
      end
    end
  end

  test "blocks redirect to cloud metadata endpoint" do
    fetcher = FetchesUrl.new(url: "https://example.com")

    new_env = { url: URI.parse("http://169.254.169.254/latest/meta-data/") }

    with_dns_stub([ "169.254.169.254" ]) do
      assert_raises(Faraday::ConnectionFailed) do
        fetcher.send(:validate_redirect_target, {}, new_env)
      end
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
    with_dns_stub([ "127.0.0.1" ]) do
      fetcher = FetchesUrl.new(url: "http://localhost/admin")
      assert_not fetcher.send(:safe_host?)
    end
  end

  test "safe_host? integration with 127.0.0.1" do
    with_dns_stub([ "127.0.0.1" ]) do
      fetcher = FetchesUrl.new(url: "http://127.0.0.1/admin")
      assert_not fetcher.send(:safe_host?)
    end
  end

  test "blocks localhost URL via call" do
    with_dns_stub([ "127.0.0.1" ]) do
      result = FetchesUrl.call(url: "http://localhost/admin")
      assert result.failure?
      assert_equal "URL not allowed", result.error
    end
  end

  test "blocks 127.0.0.1 URL via call" do
    with_dns_stub([ "127.0.0.1" ]) do
      result = FetchesUrl.call(url: "http://127.0.0.1/secret")
      assert result.failure?
      assert_equal "URL not allowed", result.error
    end
  end
end
