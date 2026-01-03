# frozen_string_literal: true

require "test_helper"

class ValidatesCharacterLimitTest < ActiveSupport::TestCase
  test "returns success when user has no limit" do
    user = users(:unlimited_user)

    result = ValidatesCharacterLimit.call(user: user, character_count: 1_000_000)

    assert result.success?
  end

  test "returns success when content is within limit" do
    user = users(:free_user)
    limit = AppConfig::Tiers::FREE_CHARACTER_LIMIT

    result = ValidatesCharacterLimit.call(user: user, character_count: limit - 1)

    assert result.success?
  end

  test "returns success when content equals limit exactly" do
    user = users(:free_user)
    limit = AppConfig::Tiers::FREE_CHARACTER_LIMIT

    result = ValidatesCharacterLimit.call(user: user, character_count: limit)

    assert result.success?
  end

  test "returns failure when content exceeds limit" do
    user = users(:free_user)
    limit = AppConfig::Tiers::FREE_CHARACTER_LIMIT

    result = ValidatesCharacterLimit.call(user: user, character_count: limit + 1)

    assert result.failure?
  end

  test "failure message includes limit and character count" do
    user = users(:free_user)
    limit = AppConfig::Tiers::FREE_CHARACTER_LIMIT
    character_count = limit + 500

    result = ValidatesCharacterLimit.call(user: user, character_count: character_count)

    assert_includes result.error, limit.to_fs(:delimited)
    assert_includes result.error, character_count.to_fs(:delimited)
    assert_includes result.error, "exceeds your plan's"
  end
end
