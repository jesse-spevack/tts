require "test_helper"

class CanClaimFreeEpisodeTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @pro_user = users(:pro_user)
    @unlimited_user = users(:unlimited_user)
  end

  test "returns true for non-free tier user" do
    assert CanClaimFreeEpisode.call(user: @pro_user)
    assert CanClaimFreeEpisode.call(user: @unlimited_user)
  end

  test "returns true for free tier user with no claims" do
    assert CanClaimFreeEpisode.call(user: @free_user)
  end

  test "returns false for free tier user with active claim" do
    podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
    podcast.users << @free_user
    episode = podcast.episodes.create!(
      title: "Test",
      author: "Author",
      description: "Desc"
    )
    FreeEpisodeClaim.create!(
      user: @free_user,
      episode: episode,
      claimed_at: Time.current
    )

    assert_not CanClaimFreeEpisode.call(user: @free_user)
  end

  test "returns true for free tier user with only released claims" do
    podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
    podcast.users << @free_user
    episode = podcast.episodes.create!(
      title: "Test",
      author: "Author",
      description: "Desc"
    )
    FreeEpisodeClaim.create!(
      user: @free_user,
      episode: episode,
      claimed_at: 1.hour.ago,
      released_at: Time.current
    )

    assert CanClaimFreeEpisode.call(user: @free_user)
  end
end
