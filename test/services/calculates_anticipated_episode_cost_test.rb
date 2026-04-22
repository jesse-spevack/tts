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
    # Standard voice at 25k → 1 credit
    assert_equal Cost.credits(1), calc(source_type: "text", text: "a" * 25_000).data
  end

  test "source_type paste uses text.length" do
    assert_equal Cost.credits(1), calc(source_type: "paste", text: "a" * 25_000).data
  end

  test "source_type extension uses text.length (API v1 treats it as text variant)" do
    assert_equal Cost.credits(1), calc(source_type: "extension", text: "a" * 25_000).data
  end

  test "source_type file uses upload.size when IO-like" do
    upload = StringIO.new("b" * 30_000)
    # StringIO responds to :size.
    @user.update!(voice_preference: "callum") # Premium + >20k → 2 credits
    assert_equal Cost.credits(2), calc(source_type: "file", upload: upload).data
  end

  test "source_type upload falls back to string length when upload is a String" do
    @user.update!(voice_preference: "callum") # Premium
    assert_equal Cost.credits(2), calc(source_type: "upload", upload: "c" * 30_000).data
  end

  # --- URL source_type: deferred cost (agent-team-7i24 + gafe) --------------
  #
  # Brick 3 killed the source_type=='url' → 1 sentinel. Gafe formalizes the
  # contract: the service returns Cost.deferred for URL without a known
  # length. ChecksEpisodeCreationPermission#check_credit_balance already
  # treats a nil cost as sufficient — callers unwrap cost.credits (nil when
  # deferred) before passing to the gate.
  #
  # ProcessesUrlEpisode re-calls the service after FetchesArticleContent
  # knows the extracted character_count. Passing source_text_length on the
  # request computes the real Cost.credits rather than returning Cost.deferred.

  test "source_type url without length override returns Cost.deferred" do
    @user.update!(voice_preference: "callum") # Premium, would otherwise be 2
    result = calc(source_type: "url", url: "https://example.com/huge-article")
    assert result.success?
    assert_equal Cost.deferred, result.data,
      "URL source_type without known length must return Cost.deferred"
  end

  test "source_type url with source_text_length override computes real cost (post-extract)" do
    # ProcessesUrlEpisode re-calls the unified service after FetchesArticleContent
    # knows the article's character_count. Passing source_text_length on a url
    # request must compute the real credit cost, not return Cost.deferred.
    @user.update!(voice_preference: "callum") # Premium + >20k → 2 credits
    result = calc(source_type: "url", url: "https://example.com/huge-article", source_text_length: 30_000)
    assert_equal Cost.credits(2), result.data
  end

  test "source_type text with source_text_length override routes post-extract (URL async path)" do
    # Alternate post-extract pattern: a caller can pass source_type: 'text' +
    # source_text_length: extracted_chars and reach the same computed cost.
    # This proves both source_types with the length override hit the same
    # calculator.
    @user.update!(voice_preference: "callum") # Premium
    assert_equal Cost.credits(2), calc(source_type: "text", source_text_length: 30_000).data
  end

  test "source_type url with short-article length override returns 1 credit (Standard voice)" do
    @user.update!(voice_preference: "felix") # Standard
    assert_equal Cost.credits(1), calc(source_type: "url", source_text_length: 5_000).data
  end

  test "unknown source_type returns Cost.credits(1) based on 0-length source" do
    # 0 <= 20k → 1 credit
    assert_equal Cost.credits(1), calc(source_type: "mystery", text: "ignored").data
  end

  # --- voice tier combinations -----------------------------------------------

  test "short text with Standard voice → 1 credit" do
    @user.update!(voice_preference: "felix")
    assert_equal Cost.credits(1), calc(source_type: "text", text: "a" * 15_000).data
  end

  test "short text with Premium voice → 1 credit" do
    @user.update!(voice_preference: "callum")
    assert_equal Cost.credits(1), calc(source_type: "text", text: "a" * 15_000).data
  end

  test "long text with Standard voice → 1 credit" do
    @user.update!(voice_preference: "felix")
    assert_equal Cost.credits(1), calc(source_type: "text", text: "a" * 30_000).data
  end

  test "long text with Premium voice → 2 credits" do
    @user.update!(voice_preference: "callum")
    assert_equal Cost.credits(2), calc(source_type: "text", text: "a" * 30_000).data
  end

  # --- user with no preference falls to catalog default (Standard) -----------

  test "user without voice_preference uses catalog default (Standard) for pricing" do
    @user.update!(voice_preference: nil)
    # Default is 'felix' (Standard) → 1 credit even at 30k
    assert_equal Cost.credits(1), calc(source_type: "text", text: "a" * 30_000).data
  end

  # --- boundary --------------------------------------------------------------

  test "exactly 20000 chars with Premium voice → 1 credit (boundary)" do
    @user.update!(voice_preference: "callum")
    assert_equal Cost.credits(1), calc(source_type: "text", text: "a" * 20_000).data
  end

  test "20001 chars with Premium voice → 2 credits" do
    @user.update!(voice_preference: "callum")
    assert_equal Cost.credits(2), calc(source_type: "text", text: "a" * 20_001).data
  end

  # --- source_text_length override -------------------------------------------
  #
  # The web cost-preview endpoint (agent-team-gq88) receives upload_length
  # from the client pre-computed (file.size) rather than an IO-like blob.
  # Callers set source_text_length on the request, bypassing source_type-based
  # extraction. Override wins even when other inputs are present.

  test "source_text_length override wins for upload source_type" do
    @user.update!(voice_preference: "callum") # Premium + >20k → 2 credits
    assert_equal Cost.credits(2), calc(source_type: "upload", source_text_length: 25_000).data
  end

  test "source_text_length override wins over text content for paste" do
    @user.update!(voice_preference: "callum") # Premium
    assert_equal Cost.credits(2), calc(source_type: "paste", text: "a" * 100, source_text_length: 25_000).data
  end

  test "source_text_length override below 20k with Premium → 1 credit" do
    @user.update!(voice_preference: "callum")
    assert_equal Cost.credits(1), calc(source_type: "upload", source_text_length: 10_000).data
  end

  private

  def calc(**kwargs)
    CalculatesAnticipatedEpisodeCost.call(EpisodeCostRequest.new(user: @user, **kwargs))
  end
end
