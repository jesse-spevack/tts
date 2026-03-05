# frozen_string_literal: true

require "test_helper"

class StripsUrlTrackingParamsTest < ActiveSupport::TestCase
  test "strips all query parameters from URL" do
    url = "https://example.com/article?utm_source=twitter&utm_medium=social"

    assert_equal "https://example.com/article", StripsUrlTrackingParams.call(url)
  end

  test "strips substack tracking parameters" do
    url = "https://alifeengineered.substack.com/p/things-you-think-are-helping-your?utm_source=post-email-title&publication_id=2598310&post_id=183704917&utm_campaign=email-post-title&isFreemail=true&r=5fkgm&triedRedirect=true&utm_medium=email"

    assert_equal "https://alifeengineered.substack.com/p/things-you-think-are-helping-your", StripsUrlTrackingParams.call(url)
  end

  test "returns URL unchanged when no query parameters" do
    url = "https://example.com/article"

    assert_equal "https://example.com/article", StripsUrlTrackingParams.call(url)
  end

  test "strips fragment identifiers" do
    url = "https://example.com/article#section-1"

    assert_equal "https://example.com/article", StripsUrlTrackingParams.call(url)
  end

  test "strips both query parameters and fragments" do
    url = "https://example.com/article?ref=homepage#comments"

    assert_equal "https://example.com/article", StripsUrlTrackingParams.call(url)
  end

  test "preserves path with trailing slash" do
    url = "https://example.com/blog/?utm_source=newsletter"

    assert_equal "https://example.com/blog/", StripsUrlTrackingParams.call(url)
  end

  test "returns original string for invalid URI" do
    url = "not a valid url at all :::"

    assert_equal url, StripsUrlTrackingParams.call(url)
  end

  test "handles URL with only a question mark" do
    url = "https://example.com/article?"

    assert_equal "https://example.com/article", StripsUrlTrackingParams.call(url)
  end
end
