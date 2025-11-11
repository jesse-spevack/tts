require "test_helper"

class PodcastMembershipTest < ActiveSupport::TestCase
  test "validates uniqueness of user_id scoped to podcast_id" do
    existing = podcast_memberships(:one)
    duplicate = PodcastMembership.new(
      user: existing.user,
      podcast: existing.podcast
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "allows same user to belong to different podcasts" do
    user = users(:one)
    podcast2 = podcasts(:two)

    # User :one already has membership to podcast :one from fixtures
    membership2 = PodcastMembership.new(user: user, podcast: podcast2)

    assert membership2.valid?
  end

  test "allows different users to belong to same podcast" do
    user2 = users(:two)
    podcast = podcasts(:one)

    # User :one already has membership to podcast :one from fixtures
    membership2 = PodcastMembership.new(user: user2, podcast: podcast)

    assert membership2.valid?
  end
end
