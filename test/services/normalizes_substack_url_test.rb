# frozen_string_literal: true

require "test_helper"

class NormalizesSubstackUrlTest < ActiveSupport::TestCase
  test "converts open.substack.com to author subdomain" do
    url = "https://open.substack.com/pub/jaymichaelson/p/ghosts-in-the-machine"

    result = NormalizesSubstackUrl.call(url: url)

    assert result.success?
    assert_equal "https://jaymichaelson.substack.com/p/ghosts-in-the-machine", result.data
  end

  test "strips tracking parameters from substack URLs" do
    url = "https://jaymichaelson.substack.com/p/ghosts?r=5fkgm&utm_campaign=post&utm_medium=web"

    result = NormalizesSubstackUrl.call(url: url)

    assert result.success?
    assert_equal "https://jaymichaelson.substack.com/p/ghosts", result.data
  end

  test "handles combined open.substack.com with tracking params" do
    url = "https://open.substack.com/pub/jaymichaelson/p/ghosts-in-the-machine?r=5fkgm&utm_campaign=post&utm_medium=web&showWelcomeOnShare=false"

    result = NormalizesSubstackUrl.call(url: url)

    assert result.success?
    assert_equal "https://jaymichaelson.substack.com/p/ghosts-in-the-machine", result.data
  end

  test "preserves non-tracking query params" do
    url = "https://author.substack.com/p/post?important_param=keep&utm_campaign=remove"

    result = NormalizesSubstackUrl.call(url: url)

    assert result.success?
    assert_equal "https://author.substack.com/p/post?important_param=keep", result.data
  end

  test "returns non-substack URLs unchanged" do
    url = "https://example.com/article?utm_campaign=test"

    result = NormalizesSubstackUrl.call(url: url)

    assert result.success?
    assert_equal "https://example.com/article?utm_campaign=test", result.data
  end

  test "returns original URL on parse error" do
    url = "not a valid url at all :::"

    result = NormalizesSubstackUrl.call(url: url)

    assert result.success?
    assert_equal url, result.data
  end

  test "handles open.substack.com with non-pub path" do
    url = "https://open.substack.com/some/other/path"

    result = NormalizesSubstackUrl.call(url: url)

    assert result.success?
    assert_equal "https://open.substack.com/some/other/path", result.data
  end

  test "rejects substack inbox URLs" do
    url = "https://substack.com/inbox/post/182789127"

    result = NormalizesSubstackUrl.call(url: url)

    assert result.failure?
    assert_match(/inbox links require login/, result.error)
  end

  test "rejects www.substack.com inbox URLs" do
    url = "https://www.substack.com/inbox/post/182789127"

    result = NormalizesSubstackUrl.call(url: url)

    assert result.failure?
    assert_match(/inbox links require login/, result.error)
  end
end
