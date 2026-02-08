require "test_helper"

class CreatesDefaultPodcastTest < ActiveSupport::TestCase
  test "creates a podcast for the user" do
    user = User.create!(email_address: "test@example.com")

    podcast = CreatesDefaultPodcast.call(user: user)

    assert_not_nil podcast
    assert_equal "test@example.com's Very Normal Podcast", podcast.title
    assert_equal "My podcast created with example.com", podcast.description
    assert_match /^podcast_[a-f0-9]{16}$/, podcast.podcast_id
  end

  test "creates a podcast membership for the user" do
    user = User.create!(email_address: "test@example.com")

    podcast = CreatesDefaultPodcast.call(user: user)

    assert_equal 1, user.podcasts.count
    assert_equal podcast, user.podcasts.first
  end

  test "podcast membership is created with user and podcast" do
    user = User.create!(email_address: "test@example.com")

    podcast = CreatesDefaultPodcast.call(user: user)

    membership = PodcastMembership.find_by(user: user, podcast: podcast)
    assert_not_nil membership
    assert_equal user, membership.user
    assert_equal podcast, membership.podcast
  end
end
