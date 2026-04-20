# frozen_string_literal: true

require "test_helper"

class CalculatesAnticipatedEpisodeCostTest < ActiveSupport::TestCase
  # Voice catalog: 'felix' Standard (DEFAULT_KEY), 'callum' Premium (ChirpHD).
  setup do
    @user = users(:one)
    @user.update!(voice_preference: "felix") # Standard by default
  end

  # --- source_type branches ---------------------------------------------------

  test "source_type text uses text.length" do
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "text", text: "a" * 25_000
    )
    assert result.success?
    # Standard voice at 25k → 1 credit
    assert_equal 1, result.data
  end

  test "source_type paste uses text.length" do
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "paste", text: "a" * 25_000
    )
    assert result.success?
    assert_equal 1, result.data
  end

  test "source_type extension uses text.length (API v1 treats it as text variant)" do
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "extension", text: "a" * 25_000
    )
    assert result.success?
    assert_equal 1, result.data
  end

  test "source_type file uses upload.size when IO-like" do
    upload = StringIO.new("b" * 30_000)
    # StringIO responds to :size.
    @user.update!(voice_preference: "callum") # Premium
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "file", upload: upload
    )
    assert result.success?
    # Premium + >20k → 2 credits
    assert_equal 2, result.data
  end

  test "source_type upload falls back to string length when upload is a String" do
    @user.update!(voice_preference: "callum") # Premium
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "upload", upload: "c" * 30_000
    )
    assert result.success?
    assert_equal 2, result.data
  end

  test "source_type url always returns 1 (URL-length shortcut)" do
    @user.update!(voice_preference: "callum") # Premium, would otherwise be 2
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "url", url: "https://example.com/huge-article"
    )
    assert result.success?
    assert_equal 1, result.data
  end

  test "unknown source_type returns cost based on 0-length source" do
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "mystery", text: "ignored"
    )
    assert result.success?
    # 0 <= 20k → 1 credit
    assert_equal 1, result.data
  end

  # --- voice tier combinations -----------------------------------------------

  test "short text with Standard voice → 1 credit" do
    @user.update!(voice_preference: "felix")
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "text", text: "a" * 15_000
    )
    assert_equal 1, result.data
  end

  test "short text with Premium voice → 1 credit" do
    @user.update!(voice_preference: "callum")
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "text", text: "a" * 15_000
    )
    assert_equal 1, result.data
  end

  test "long text with Standard voice → 1 credit" do
    @user.update!(voice_preference: "felix")
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "text", text: "a" * 30_000
    )
    assert_equal 1, result.data
  end

  test "long text with Premium voice → 2 credits" do
    @user.update!(voice_preference: "callum")
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "text", text: "a" * 30_000
    )
    assert_equal 2, result.data
  end

  # --- user with no preference falls to catalog default (Standard) -----------

  test "user without voice_preference uses catalog default (Standard) for pricing" do
    @user.update!(voice_preference: nil)
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "text", text: "a" * 30_000
    )
    # Default is 'felix' (Standard) → 1 credit even at 30k
    assert_equal 1, result.data
  end

  # --- boundary --------------------------------------------------------------

  test "exactly 20000 chars with Premium voice → 1 credit (boundary)" do
    @user.update!(voice_preference: "callum")
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "text", text: "a" * 20_000
    )
    assert_equal 1, result.data
  end

  test "20001 chars with Premium voice → 2 credits" do
    @user.update!(voice_preference: "callum")
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "text", text: "a" * 20_001
    )
    assert_equal 2, result.data
  end
end
