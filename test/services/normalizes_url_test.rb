# frozen_string_literal: true

require "test_helper"

class NormalizesUrlTest < ActiveSupport::TestCase
  test "converts open.substack.com to author subdomain" do
    url = "https://open.substack.com/pub/jaymichaelson/p/ghosts-in-the-machine"

    result = NormalizesUrl.call(url: url)

    assert_equal "https://jaymichaelson.substack.com/p/ghosts-in-the-machine", result
  end

  test "strips tracking parameters from substack URLs" do
    url = "https://jaymichaelson.substack.com/p/ghosts?r=5fkgm&utm_campaign=post&utm_medium=web"

    result = NormalizesUrl.call(url: url)

    assert_equal "https://jaymichaelson.substack.com/p/ghosts", result
  end

  test "handles combined open.substack.com with tracking params" do
    url = "https://open.substack.com/pub/jaymichaelson/p/ghosts-in-the-machine?r=5fkgm&utm_campaign=post&utm_medium=web&showWelcomeOnShare=false"

    result = NormalizesUrl.call(url: url)

    assert_equal "https://jaymichaelson.substack.com/p/ghosts-in-the-machine", result
  end

  test "preserves non-tracking query params" do
    url = "https://author.substack.com/p/post?important_param=keep&utm_campaign=remove"

    result = NormalizesUrl.call(url: url)

    assert_equal "https://author.substack.com/p/post?important_param=keep", result
  end

  test "returns non-substack URLs unchanged" do
    url = "https://example.com/article?utm_campaign=test"

    result = NormalizesUrl.call(url: url)

    assert_equal "https://example.com/article?utm_campaign=test", result
  end

  test "returns original URL on parse error" do
    url = "not a valid url at all :::"

    result = NormalizesUrl.call(url: url)

    assert_equal url, result
  end

  test "handles open.substack.com with non-pub path" do
    url = "https://open.substack.com/some/other/path"

    result = NormalizesUrl.call(url: url)

    assert_equal "https://open.substack.com/some/other/path", result
  end
end
