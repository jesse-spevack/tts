require "test_helper"

class FreeEpisodeClaimTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
    @podcast = Podcast.create!(podcast_id: SecureRandom.uuid, title: "Test Podcast")
    @podcast.users << @user
    @episode = @podcast.episodes.create!(
      title: "Test Episode",
      author: "Author",
      description: "Description"
    )
  end

  test "belongs to user" do
    claim = FreeEpisodeClaim.create!(
      user: @user,
      episode: @episode,
      claimed_at: Time.current
    )

    assert_equal @user, claim.user
  end

  test "belongs to episode" do
    claim = FreeEpisodeClaim.create!(
      user: @user,
      episode: @episode,
      claimed_at: Time.current
    )

    assert_equal @episode, claim.episode
  end

  test "active scope returns claims without released_at" do
    active_claim = FreeEpisodeClaim.create!(
      user: @user,
      episode: @episode,
      claimed_at: Time.current
    )

    other_user = users(:basic_user)
    other_episode = @podcast.episodes.create!(
      title: "Other Episode",
      author: "Author",
      description: "Description"
    )
    released_claim = FreeEpisodeClaim.create!(
      user: other_user,
      episode: other_episode,
      claimed_at: 1.hour.ago,
      released_at: Time.current
    )

    assert_includes FreeEpisodeClaim.active, active_claim
    assert_not_includes FreeEpisodeClaim.active, released_claim
  end

  test "requires user" do
    claim = FreeEpisodeClaim.new(episode: @episode, claimed_at: Time.current)
    assert_not claim.valid?
    assert_includes claim.errors[:user], "must exist"
  end

  test "requires episode" do
    claim = FreeEpisodeClaim.new(user: @user, claimed_at: Time.current)
    assert_not claim.valid?
    assert_includes claim.errors[:episode], "must exist"
  end

  test "requires claimed_at" do
    claim = FreeEpisodeClaim.new(user: @user, episode: @episode)
    assert_not claim.valid?
    assert_includes claim.errors[:claimed_at], "can't be blank"
  end
end
