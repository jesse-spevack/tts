require "test_helper"

class CreateUserTest < ActiveSupport::TestCase
  test "creates a user with the given email" do
    result = CreateUser.call(email_address: "newuser@example.com")

    assert result.success?
    assert_not_nil result.user
    assert_equal "newuser@example.com", result.user.email_address
  end

  test "creates a default podcast for the user" do
    result = CreateUser.call(email_address: "newuser@example.com")

    assert result.success?
    assert_not_nil result.podcast
    assert_equal "newuser@example.com's Very Normal Podcast", result.podcast.title
  end

  test "creates user and podcast in a transaction" do
    result = CreateUser.call(email_address: "newuser@example.com")

    assert result.success?
    assert_equal 1, result.user.podcasts.count
    assert_equal result.podcast, result.user.podcasts.first
  end

  test "returns failure if user creation fails" do
    result = CreateUser.call(email_address: "invalid")

    assert_not result.success?
    assert_nil result.user
    assert_nil result.podcast
  end

  test "rolls back podcast creation if transaction fails" do
    # Mock CreateDefaultPodcast to raise an error
    CreateDefaultPodcast.stub :call, ->(_) { raise ActiveRecord::Rollback } do
      initial_user_count = User.count
      initial_podcast_count = Podcast.count

      result = CreateUser.call(email_address: "rollback@example.com")

      # Transaction should rollback both user and podcast
      assert_equal initial_user_count, User.count
      assert_equal initial_podcast_count, Podcast.count
    end
  end
end
