# frozen_string_literal: true

require "test_helper"

class MaxCharactersForUserTest < ActiveSupport::TestCase
  test "returns FREE limit for free tier" do
    user = users(:one)
    user.update!(tier: :free)

    result = MaxCharactersForUser.call(user: user)

    assert_equal EpisodeSubmissionValidator::MAX_CHARACTERS_FREE, result
  end

  test "returns PREMIUM limit for premium tier" do
    user = users(:one)
    user.update!(tier: :premium)

    result = MaxCharactersForUser.call(user: user)

    assert_equal EpisodeSubmissionValidator::MAX_CHARACTERS_PREMIUM, result
  end

  test "returns nil for unlimited tier" do
    user = users(:one)
    user.update!(tier: :unlimited)

    result = MaxCharactersForUser.call(user: user)

    assert_nil result
  end
end
