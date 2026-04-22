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

  # --- URL source_type: deferred cost (agent-team-7i24) ---------------------
  #
  # Brick 3 kills the source_type=='url' → 1 sentinel. The real article length
  # isn't known at controller-submit / preview time for URL episodes, so the
  # unified service returns Result.success(nil) and callers explicitly handle
  # the deferred case (ChecksEpisodeCreationPermission.check_credit_balance
  # already short-circuits on nil cost — see checks_episode_creation_permission.rb:43).
  #
  # ProcessesUrlEpisode then re-calls this service with the extracted length
  # (pass-through via source_type: 'text' + source_text_length: extracted_chars)
  # to compute the real deferred cost before debiting.

  test "source_type url without length override returns nil (deferred cost)" do
    @user.update!(voice_preference: "callum") # Premium, would otherwise be 2
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user, source_type: "url", url: "https://example.com/huge-article"
    )
    assert result.success?
    assert_nil result.data,
      "URL source_type without known length must return nil, not a magic 1 sentinel"
  end

  test "source_type url with source_text_length override computes real cost (post-extract)" do
    # ProcessesUrlEpisode re-calls the unified service after FetchesArticleContent
    # knows the article's character_count. Passing source_type: 'url' +
    # source_text_length: extracted_chars must compute the real credit cost,
    # not short-circuit to nil.
    @user.update!(voice_preference: "callum") # Premium
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user,
      source_type: "url",
      url: "https://example.com/huge-article",
      source_text_length: 30_000
    )
    assert result.success?
    # Premium + >20k → 2 credits
    assert_equal 2, result.data
  end

  test "source_type text with source_text_length override routes post-extract (URL async path)" do
    # Alternate post-extract pattern: ProcessesUrlEpisode can pass
    # source_type: 'text' + source_text_length: extracted_chars and reach
    # the same computed cost. This proves both source_types with the
    # length override hit the same calculator.
    @user.update!(voice_preference: "callum") # Premium
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user,
      source_type: "text",
      source_text_length: 30_000
    )
    assert result.success?
    assert_equal 2, result.data
  end

  test "source_type url with short-article length override returns 1 (Standard voice)" do
    @user.update!(voice_preference: "felix") # Standard
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user,
      source_type: "url",
      source_text_length: 5_000
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

  # --- source_text_length override -------------------------------------------
  #
  # The web cost-preview endpoint (agent-team-gq88) receives upload_length
  # from the client pre-computed (file.size) rather than an IO-like blob.
  # Callers can pass source_text_length: directly, bypassing the branching
  # on source_type. Override wins even when other inputs are present.

  test "source_text_length override wins for upload source_type" do
    @user.update!(voice_preference: "callum") # Premium
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user,
      source_type: "upload",
      source_text_length: 25_000
    )
    assert result.success?
    # Premium + >20k → 2 credits
    assert_equal 2, result.data
  end

  test "source_text_length override wins over text content for paste" do
    @user.update!(voice_preference: "callum") # Premium
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user,
      source_type: "paste",
      text: "a" * 100, # ignored
      source_text_length: 25_000
    )
    assert_equal 2, result.data
  end

  test "source_text_length override below 20k with Premium → 1 credit" do
    @user.update!(voice_preference: "callum")
    result = CalculatesAnticipatedEpisodeCost.call(
      user: @user,
      source_type: "upload",
      source_text_length: 10_000
    )
    assert_equal 1, result.data
  end
end
