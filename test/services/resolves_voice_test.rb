# frozen_string_literal: true

require "test_helper"

class ResolvesVoiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  # Explicit request
  test "returns requested voice when a valid key is provided" do
    result = ResolvesVoice.call(requested_key: "callum", user: @user)

    assert result.success?
    assert_equal "callum", result.data.key
    assert result.data.premium?
  end

  test "requested voice wins over user's saved preference" do
    @user.update!(voice_preference: "felix")

    result = ResolvesVoice.call(requested_key: "lark", user: @user)

    assert result.success?
    assert_equal "lark", result.data.key
  end

  test "invalid requested key returns failure(:invalid_voice)" do
    result = ResolvesVoice.call(requested_key: "not_a_voice", user: @user)

    assert result.failure?
    assert_equal :invalid_voice, result.error
  end

  test "invalid requested key returns failure for anonymous callers too" do
    result = ResolvesVoice.call(requested_key: "not_a_voice", user: nil)

    assert result.failure?
    assert_equal :invalid_voice, result.error
  end

  # User saved preference
  test "falls back to user's voice_preference when no voice requested" do
    @user.update!(voice_preference: "nash")

    result = ResolvesVoice.call(requested_key: nil, user: @user)

    assert result.success?
    assert_equal "nash", result.data.key
  end

  test "empty string requested_key is treated as absent (falls to preference)" do
    @user.update!(voice_preference: "gemma")

    result = ResolvesVoice.call(requested_key: "", user: @user)

    assert result.success?
    assert_equal "gemma", result.data.key
  end

  # Catalog default fallback
  test "anonymous caller with no requested voice gets catalog default" do
    result = ResolvesVoice.call(requested_key: nil, user: nil)

    assert result.success?
    assert_equal Voice::DEFAULT_KEY, result.data.key
  end

  test "authenticated caller with no preference and no requested voice gets catalog default" do
    @user.update!(voice_preference: nil)

    result = ResolvesVoice.call(requested_key: nil, user: @user)

    assert result.success?
    assert_equal Voice::DEFAULT_KEY, result.data.key
  end

  test "stale user preference (no longer in catalog) silently falls to default" do
    # Bypass validation to simulate a preference that used to be valid but
    # is no longer in the catalog.
    @user.update_column(:voice_preference, "retired_voice")

    result = ResolvesVoice.call(requested_key: nil, user: @user)

    assert result.success?,
      "stale preference should not fail the request — silently use default"
    assert_equal Voice::DEFAULT_KEY, result.data.key
  end

  # Catalog default is the confirmed Standard-tier voice
  test "catalog default is felix (Standard tier) post-research flip" do
    assert_equal "felix", Voice::DEFAULT_KEY

    result = ResolvesVoice.call(requested_key: nil, user: nil)
    assert result.data.standard?,
      "default voice must be Standard tier — callers who omit voice should land on the cheaper price"
  end
end
