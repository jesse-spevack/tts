# frozen_string_literal: true

require "test_helper"

class NormalizesTwitterUrlTest < ActiveSupport::TestCase
  test "normalizes twitter.com to x.com" do
    result = NormalizesTwitterUrl.call(url: "https://twitter.com/user/status/123")

    assert result.success?
    assert_equal "https://x.com/user/status/123", result.data
  end

  test "normalizes www.twitter.com to x.com" do
    result = NormalizesTwitterUrl.call(url: "https://www.twitter.com/user/status/123")

    assert result.success?
    assert_equal "https://x.com/user/status/123", result.data
  end

  test "normalizes mobile.twitter.com to x.com" do
    result = NormalizesTwitterUrl.call(url: "https://mobile.twitter.com/user/status/123")

    assert result.success?
    assert_equal "https://x.com/user/status/123", result.data
  end

  test "normalizes www.x.com to x.com" do
    result = NormalizesTwitterUrl.call(url: "https://www.x.com/user/status/123")

    assert result.success?
    assert_equal "https://x.com/user/status/123", result.data
  end

  test "keeps x.com URLs as-is" do
    result = NormalizesTwitterUrl.call(url: "https://x.com/user/status/123")

    assert result.success?
    assert_equal "https://x.com/user/status/123", result.data
  end

  test "preserves query params for downstream stripping" do
    result = NormalizesTwitterUrl.call(url: "https://x.com/user/status/123?s=20&t=abc")

    assert result.success?
    assert_equal "https://x.com/user/status/123?s=20&t=abc", result.data
  end

  test "returns non-twitter URLs unchanged" do
    result = NormalizesTwitterUrl.call(url: "https://example.com/article")

    assert result.success?
    assert_equal "https://example.com/article", result.data
  end

  test "returns original URL on parse error" do
    url = "not a valid url at all :::"

    result = NormalizesTwitterUrl.call(url: url)

    assert result.success?
    assert_equal url, result.data
  end

  test "normalizes http to https" do
    result = NormalizesTwitterUrl.call(url: "http://twitter.com/user/status/123")

    assert result.success?
    assert_equal "https://x.com/user/status/123", result.data
  end

  # Class method tests

  test ".twitter_url? returns true for twitter.com" do
    assert NormalizesTwitterUrl.twitter_url?("https://twitter.com/user/status/123")
  end

  test ".twitter_url? returns true for x.com" do
    assert NormalizesTwitterUrl.twitter_url?("https://x.com/user/status/123")
  end

  test ".twitter_url? returns true for mobile.twitter.com" do
    assert NormalizesTwitterUrl.twitter_url?("https://mobile.twitter.com/user/status/123")
  end

  test ".twitter_url? returns false for non-twitter URLs" do
    refute NormalizesTwitterUrl.twitter_url?("https://example.com/article")
  end

  test ".twitter_url? returns false for invalid URLs" do
    refute NormalizesTwitterUrl.twitter_url?("not a url :::")
  end

  test ".extract_tweet_id returns tweet ID from status URL" do
    assert_equal "123456789", NormalizesTwitterUrl.extract_tweet_id("https://x.com/user/status/123456789")
  end

  test ".extract_tweet_id returns nil for non-status URL" do
    assert_nil NormalizesTwitterUrl.extract_tweet_id("https://x.com/user")
  end

  test ".extract_tweet_id returns nil for invalid URL" do
    assert_nil NormalizesTwitterUrl.extract_tweet_id("not a url :::")
  end

  test ".extract_tweet_id handles URL with trailing path segments" do
    assert_equal "123456789", NormalizesTwitterUrl.extract_tweet_id("https://x.com/user/status/123456789/photo/1")
  end

  test ".extract_username returns username from status URL" do
    assert_equal "elonmusk", NormalizesTwitterUrl.extract_username("https://x.com/elonmusk/status/123456789")
  end

  test ".extract_username returns nil for non-status URL" do
    assert_nil NormalizesTwitterUrl.extract_username("https://x.com/user")
  end

  test ".extract_username returns nil for invalid URL" do
    assert_nil NormalizesTwitterUrl.extract_username("not a url :::")
  end
end
