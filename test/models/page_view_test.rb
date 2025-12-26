require "test_helper"

class PageViewTest < ActiveSupport::TestCase
  test "creates page view with required attributes" do
    page_view = PageView.create!(
      path: "/",
      visitor_hash: "abc123",
      user_agent: "Mozilla/5.0"
    )

    assert page_view.persisted?
    assert_equal "/", page_view.path
  end

  test "allows nil referrer" do
    page_view = PageView.new(
      path: "/",
      visitor_hash: "abc123",
      user_agent: "Mozilla/5.0",
      referrer: nil
    )

    assert page_view.valid?
  end

  test "extracts referrer_host from referrer" do
    page_view = PageView.new(
      path: "/",
      visitor_hash: "abc123",
      user_agent: "Mozilla/5.0",
      referrer: "https://www.google.com/search?q=tts"
    )
    page_view.valid?

    assert_equal "www.google.com", page_view.referrer_host
  end

  test "handles nil referrer when extracting host" do
    page_view = PageView.new(
      path: "/",
      visitor_hash: "abc123",
      user_agent: "Mozilla/5.0",
      referrer: nil
    )

    assert_nil page_view.referrer_host
  end

  test "handles malformed referrer gracefully" do
    page_view = PageView.new(
      path: "/",
      visitor_hash: "abc123",
      user_agent: "Mozilla/5.0",
      referrer: "not a valid url"
    )
    page_view.valid?

    assert_nil page_view.referrer_host
  end

  # Query method tests
  test ".stats returns total_views and unique_visitors since date" do
    PageView.create!(path: "/", visitor_hash: "abc", user_agent: "test", created_at: 2.days.ago)
    PageView.create!(path: "/", visitor_hash: "abc", user_agent: "test", created_at: 1.day.ago)
    PageView.create!(path: "/", visitor_hash: "def", user_agent: "test", created_at: 1.day.ago)
    PageView.create!(path: "/old", visitor_hash: "xyz", user_agent: "test", created_at: 10.days.ago)

    stats = PageView.stats(since: 7.days.ago)

    assert_equal 3, stats[:total_views]
    assert_equal 2, stats[:unique_visitors]
  end

  test ".stats returns views_by_page ordered by count" do
    PageView.create!(path: "/", visitor_hash: "a", user_agent: "test")
    PageView.create!(path: "/", visitor_hash: "b", user_agent: "test")
    PageView.create!(path: "/how-it-sounds", visitor_hash: "c", user_agent: "test")

    stats = PageView.stats(since: 7.days.ago)

    assert_equal({ "/" => 2, "/how-it-sounds" => 1 }, stats[:views_by_page])
  end

  test ".top_referrers returns referrer hosts ordered by count" do
    PageView.create!(path: "/", visitor_hash: "a", user_agent: "test", referrer: "https://google.com/search")
    PageView.create!(path: "/", visitor_hash: "b", user_agent: "test", referrer: "https://google.com/search")
    PageView.create!(path: "/", visitor_hash: "c", user_agent: "test", referrer: "https://twitter.com/post")
    PageView.create!(path: "/", visitor_hash: "d", user_agent: "test", referrer: nil)

    referrers = PageView.top_referrers(since: 7.days.ago, limit: 10)

    assert_equal({ "google.com" => 2, "twitter.com" => 1, nil => 1 }, referrers)
  end

  test ".daily_views returns views grouped by date" do
    PageView.create!(path: "/", visitor_hash: "a", user_agent: "test", created_at: Date.current)
    PageView.create!(path: "/", visitor_hash: "b", user_agent: "test", created_at: Date.current)
    PageView.create!(path: "/", visitor_hash: "c", user_agent: "test", created_at: 1.day.ago)

    daily = PageView.daily_views(since: 7.days.ago)

    assert_equal 2, daily[Date.current.to_s]
    assert_equal 1, daily[1.day.ago.to_date.to_s]
  end
end
