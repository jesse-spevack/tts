# frozen_string_literal: true

require "test_helper"

class CalculatesMaxCharactersForUserTest < ActiveSupport::TestCase
  test "returns FREE limit for free tier" do
    user = users(:one)
    user.update!(tier: :free)

    result = CalculatesMaxCharactersForUser.call(user: user)

    assert_equal AppConfig::Tiers::FREE_CHARACTER_LIMIT, result
  end

  test "returns PREMIUM limit for premium tier" do
    user = users(:one)
    user.update!(tier: :premium)

    result = CalculatesMaxCharactersForUser.call(user: user)

    assert_equal AppConfig::Tiers::PREMIUM_CHARACTER_LIMIT, result
  end

  test "returns nil for unlimited tier" do
    user = users(:one)
    user.update!(tier: :unlimited)

    result = CalculatesMaxCharactersForUser.call(user: user)

    assert_nil result
  end
end
