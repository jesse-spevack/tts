require "test_helper"

class ReleaseFreeEpisodeClaimTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
    @podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test")
    @podcast.users << @free_user
    @episode = @podcast.episodes.create!(
      title: "Test",
      author: "Author",
      description: "Desc"
    )
  end

  test "releases active claim for episode" do
    claim = FreeEpisodeClaim.create!(
      user: @free_user,
      episode: @episode,
      claimed_at: Time.current
    )

    result = ReleaseFreeEpisodeClaim.call(episode: @episode)

    assert_equal claim, result
    assert_not_nil result.released_at
  end

  test "returns nil when no active claim exists" do
    result = ReleaseFreeEpisodeClaim.call(episode: @episode)

    assert_nil result
  end

  test "returns nil when claim already released" do
    FreeEpisodeClaim.create!(
      user: @free_user,
      episode: @episode,
      claimed_at: 1.hour.ago,
      released_at: 30.minutes.ago
    )

    result = ReleaseFreeEpisodeClaim.call(episode: @episode)

    assert_nil result
  end

  test "is idempotent - calling twice is safe" do
    FreeEpisodeClaim.create!(
      user: @free_user,
      episode: @episode,
      claimed_at: Time.current
    )

    first_result = ReleaseFreeEpisodeClaim.call(episode: @episode)
    second_result = ReleaseFreeEpisodeClaim.call(episode: @episode)

    assert_not_nil first_result
    assert_nil second_result
  end
end
