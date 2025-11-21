require "test_helper"

class EpisodeSubmissionValidatorTest < ActiveSupport::TestCase
  test "returns nil max_characters for unlimited tier users" do
    user = users(:unlimited_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_nil result.max_characters
    assert result.unlimited?
  end

  test "returns 10_000 max_characters for free tier users" do
    user = users(:free_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 10_000, result.max_characters
    assert_not result.unlimited?
  end

  test "returns 25_000 max_characters for basic tier users" do
    user = users(:basic_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 25_000, result.max_characters
    assert_not result.unlimited?
  end

  test "returns 50_000 max_characters for plus tier users" do
    user = users(:plus_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 50_000, result.max_characters
    assert_not result.unlimited?
  end

  test "returns 50_000 max_characters for premium tier users" do
    user = users(:premium_user)

    result = EpisodeSubmissionValidator.call(user: user)

    assert_equal 50_000, result.max_characters
    assert_not result.unlimited?
  end
end
