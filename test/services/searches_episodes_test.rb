require "test_helper"

class SearchesEpisodesTest < ActiveSupport::TestCase
  setup do
    @podcast = podcasts(:one)
    @other_podcast = podcasts(:two)

    # Clear existing episodes to isolate search behavior
    Episode.unscoped.delete_all

    # Use url source_type to avoid source_text length validation
    @ep_alice = Episode.create!(
      podcast: @podcast, user: users(:one),
      title: "Alice Episode", author: "Alice Johnson",
      description: "Test episode", source_type: :url,
      source_url: "https://example.com/alice",
      source_text: "Ruby on Rails tutorial content", status: :complete
    )
    @ep_bob = Episode.create!(
      podcast: @podcast, user: users(:one),
      title: "Bob Episode", author: "Bob Smith",
      description: "Test episode", source_type: :url,
      source_url: "https://blog.example.com/react-hooks",
      source_text: "JavaScript patterns and practices", status: :complete
    )
    @ep_carol = Episode.create!(
      podcast: @podcast, user: users(:one),
      title: "Carol Episode", author: "Carol Wu",
      description: "Test episode", source_type: :url,
      source_url: "https://news.ycombinator.com/item",
      source_text: "Startup advice for founders and builders", status: :complete
    )
    @ep_other = Episode.create!(
      podcast: @other_podcast, user: users(:two),
      title: "Other Podcast Ep", author: "Alice Johnson",
      description: "Test episode", source_type: :url,
      source_url: "https://example.com/other",
      source_text: "Should not appear in results", status: :complete
    )
  end

  test "blank query returns all podcast episodes" do
    episodes = SearchesEpisodes.call(podcast: @podcast, query: nil)

    assert_equal 3, episodes.count
  end

  test "empty string query returns all podcast episodes" do
    episodes = SearchesEpisodes.call(podcast: @podcast, query: "")

    assert_equal 3, episodes.count
  end

  test "matches title partial" do
    episodes = SearchesEpisodes.call(podcast: @podcast, query: "Alice Episode")

    assert_includes episodes, @ep_alice
    refute_includes episodes, @ep_bob
  end

  test "matches author partial case-insensitive" do
    episodes = SearchesEpisodes.call(podcast: @podcast, query: "alice")

    assert_includes episodes, @ep_alice
    refute_includes episodes, @ep_bob
  end

  test "matches source_url partial" do
    episodes = SearchesEpisodes.call(podcast: @podcast, query: "blog.example.com")

    assert_includes episodes, @ep_bob
    refute_includes episodes, @ep_alice
  end

  test "matches source_text partial" do
    episodes = SearchesEpisodes.call(podcast: @podcast, query: "startup")

    assert_includes episodes, @ep_carol
    refute_includes episodes, @ep_alice
  end

  test "does not return other podcast episodes" do
    episodes = SearchesEpisodes.call(podcast: @podcast, query: "alice")

    refute_includes episodes, @ep_other
  end

  test "handles special LIKE characters" do
    ep_special = Episode.create!(
      podcast: @podcast, user: users(:one),
      title: "Special", author: "100% done",
      description: "Test episode", source_type: :url,
      source_url: "https://example.com/special",
      source_text: "test_underscore content", status: :complete
    )

    episodes = SearchesEpisodes.call(podcast: @podcast, query: "100%")

    assert_includes episodes, ep_special

    episodes2 = SearchesEpisodes.call(podcast: @podcast, query: "test_underscore")
    assert_includes episodes2, ep_special
  end

  test "returns results ordered newest first" do
    episodes = SearchesEpisodes.call(podcast: @podcast, query: "")

    assert_equal @ep_carol, episodes.first
  end

  test "no matches returns empty relation" do
    episodes = SearchesEpisodes.call(podcast: @podcast, query: "zzzznoexist")

    assert_equal 0, episodes.count
  end
end
