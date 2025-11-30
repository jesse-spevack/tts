require "test_helper"

class ClaimFreeEpisodeTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @pro_user = users(:pro_user)
    @podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
    @podcast.users << @free_user
    @episode = @podcast.episodes.create!(
      title: "Test",
      author: "Author",
      description: "Desc"
    )
  end

  test "creates claim for free tier user" do
    result = ClaimFreeEpisode.call(user: @free_user, episode: @episode)

    assert_instance_of FreeEpisodeClaim, result
    assert_equal @free_user, result.user
    assert_equal @episode, result.episode
    assert_not_nil result.claimed_at
    assert_nil result.released_at
  end

  test "returns nil for non-free tier user" do
    result = ClaimFreeEpisode.call(user: @pro_user, episode: @episode)

    assert_nil result
    assert_equal 0, FreeEpisodeClaim.count
  end

  test "persists the claim to database" do
    assert_difference "FreeEpisodeClaim.count", 1 do
      ClaimFreeEpisode.call(user: @free_user, episode: @episode)
    end
  end
end
