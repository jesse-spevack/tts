require "test_helper"

class PodcastTest < ActiveSupport::TestCase
  test "generates podcast_id on create" do
    podcast = Podcast.create!(title: "Test", description: "Test")

    assert_not_nil podcast.podcast_id
    assert_match(/\Apodcast_[a-f0-9]{16}\z/, podcast.podcast_id)
  end

  test "validates presence of podcast_id" do
    podcast = Podcast.create(title: "Test", description: "Test")
    podcast.update(podcast_id: nil)

    assert_not podcast.valid?
    assert_includes podcast.errors[:podcast_id], "can't be blank"
  end

  test "validates uniqueness of podcast_id" do
    existing = podcasts(:one)
    podcast = Podcast.new(podcast_id: existing.podcast_id, title: "Test", description: "Test")

    assert_not podcast.valid?
    assert_includes podcast.errors[:podcast_id], "has already been taken"
  end

  test "feed_url returns correct URL" do
    podcast = podcasts(:one)
    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "podcast-bucket")

    expected_url = "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast.podcast_id}/feed.xml"
    assert_equal expected_url, podcast.feed_url
  end

  test "feed_url returns nil when podcast_id is blank" do
    podcast = Podcast.new

    assert_nil podcast.feed_url
  end

  test "destroys associated episodes when destroyed" do
    podcast = podcasts(:one)
    episode = podcast.episodes.create!(
      title: "Test Episode",
      author: "Test Author",
      description: "Test Description",
      status: "pending"
    )

    episode_count = podcast.episodes.count

    assert_difference "Episode.count", -episode_count do
      podcast.destroy
    end
  end

  test "destroys associated podcast_memberships when destroyed" do
    podcast = podcasts(:one)

    assert_difference "PodcastMembership.count", -1 do
      podcast.destroy
    end
  end
end
