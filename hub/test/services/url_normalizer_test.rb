# frozen_string_literal: true

require "test_helper"

class UrlNormalizerTest < ActiveSupport::TestCase
  test "converts open.substack.com to author subdomain" do
    url = "https://open.substack.com/pub/jaymichaelson/p/ghosts-in-the-machine"

    result = UrlNormalizer.call(url: url)

    assert_equal "https://jaymichaelson.substack.com/p/ghosts-in-the-machine", result
  end
end
