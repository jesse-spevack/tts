require "test_helper"

class TrackableTest < ActionDispatch::IntegrationTest
  test "tracks page view for anonymous visitor" do
    assert_difference "PageView.count", 1 do
      get root_url
    end

    page_view = PageView.last
    assert_equal "/", page_view.path
    assert_not_nil page_view.visitor_hash
  end

  test "captures referrer from request header" do
    assert_difference "PageView.count", 1 do
      get root_url, headers: { "HTTP_REFERER" => "https://google.com/search" }
    end

    page_view = PageView.last
    assert_equal "https://google.com/search", page_view.referrer
    assert_equal "google.com", page_view.referrer_host
  end

  test "does not track logged in users" do
    user = users(:one)
    token = GenerateAuthToken.call(user: user)
    get auth_url, params: { token: token }

    assert_no_difference "PageView.count" do
      get root_url
    end
  end

  test "does not track bot requests" do
    assert_no_difference "PageView.count" do
      get root_url, headers: { "HTTP_USER_AGENT" => "Googlebot/2.1" }
    end
  end

  test "generates different visitor hash each day" do
    get root_url
    first_hash = PageView.last.visitor_hash

    travel 1.day do
      get root_url
    end
    second_hash = PageView.last.visitor_hash

    assert_not_equal first_hash, second_hash
  end

  test "generates same visitor hash within same day" do
    get root_url
    first_hash = PageView.last.visitor_hash

    get how_it_sounds_url
    second_hash = PageView.last.visitor_hash

    assert_equal first_hash, second_hash
  end
end
