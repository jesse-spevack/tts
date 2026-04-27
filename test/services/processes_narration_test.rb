# frozen_string_literal: true

require "test_helper"

class ProcessesNarrationTest < ActiveSupport::TestCase
  setup do
    @narration = narrations(:one)
    assert_equal "pending", @narration.status
    assert_equal "url", @narration.source_type

    Mocktail.replace(FetchesUrl)
    Mocktail.replace(ProcessesWithLlm)
    Mocktail.replace(SynthesizesAudio)
    Mocktail.replace(CloudStorage)
  end

  teardown do
    Mocktail.reset
  end

  # ── Happy path: URL narration ──────────────────────────────────────────

  test "processes URL narration end-to-end: fetch, LLM, synthesize, upload, complete" do
    stub_successful_fetch
    stub_successful_llm
    stub_successful_audio_synthesis
    stub_cloud_storage

    ProcessesNarration.call(narration: @narration)

    @narration.reload
    assert_equal "complete", @narration.status
    assert_equal "Real Title", @narration.title
    assert_equal "John Doe", @narration.author
    assert_equal "A great article.", @narration.description
    assert_not_nil @narration.gcs_episode_id
    assert_equal 18, @narration.audio_size_bytes  # "fake audio content".bytesize
    assert_not_nil @narration.processing_started_at
    assert_not_nil @narration.processing_completed_at
  end

  test "transitions through preparing → processing → complete" do
    statuses = []

    @narration.define_singleton_method(:update!) do |**attrs|
      statuses << attrs[:status] if attrs[:status]
      super(**attrs)
    end

    stub_successful_fetch
    stub_successful_llm
    stub_successful_audio_synthesis
    stub_cloud_storage

    ProcessesNarration.call(narration: @narration)

    assert_equal [ :preparing, :processing, :complete ], statuses
  end

  # ── Happy path: text narration ─────────────────────────────────────────

  test "processes text narration without fetching URL" do
    text_narration = Narration.create!(
      mpp_payment: MppPayment.create!(amount_cents: 150, currency: "usd", status: :completed, user: users(:one)),
      title: "Text Narration",
      source_type: :text,
      source_text: "This is pasted text content for narration.",
      expires_at: 24.hours.from_now
    )

    stub_successful_llm
    stub_successful_audio_synthesis
    stub_cloud_storage

    ProcessesNarration.call(narration: text_narration)

    text_narration.reload
    assert_equal "complete", text_narration.status
    assert_not_nil text_narration.gcs_episode_id
  end

  test "text narration does not call FetchesArticleContent" do
    Mocktail.replace(FetchesArticleContent)

    text_narration = Narration.create!(
      mpp_payment: MppPayment.create!(amount_cents: 150, currency: "usd", status: :completed, user: users(:one)),
      title: "Text Narration",
      source_type: :text,
      source_text: "This is pasted text content for narration.",
      expires_at: 24.hours.from_now
    )

    stub_successful_llm
    stub_successful_audio_synthesis
    stub_cloud_storage

    ProcessesNarration.call(narration: text_narration)

    verify(times: 0) { |m| FetchesArticleContent.call(url: m.any) }
  end

  # ── Error handling ─────────────────────────────────────────────────────

  test "marks narration as failed when URL fetch fails" do
    Mocktail.replace(FetchesJinaContent)

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.failure("Could not fetch URL") }
    stubs { |m| FetchesJinaContent.call(url: m.any) }.with { Result.failure("Jina failed too") }

    ProcessesNarration.call(narration: @narration)

    @narration.reload
    assert_equal "failed", @narration.status
    assert_equal "Could not fetch URL", @narration.error_message
  end

  test "marks narration as failed when LLM processing fails" do
    stub_successful_fetch
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { Result.failure("LLM error") }

    ProcessesNarration.call(narration: @narration)

    @narration.reload
    assert_equal "failed", @narration.status
    assert_equal "LLM error", @narration.error_message
  end

  test "marks narration as failed when audio synthesis raises" do
    stub_successful_fetch
    stub_successful_llm

    mock_synthesizer = Mocktail.of(SynthesizesAudio)
    stubs { |m| mock_synthesizer.call(text: m.any, voice: m.any) }.with { raise StandardError, "TTS API error" }
    stubs { |m| SynthesizesAudio.new(config: m.any) }.with { mock_synthesizer }

    ProcessesNarration.call(narration: @narration)

    @narration.reload
    assert_equal "failed", @narration.status
    assert_equal "TTS API error", @narration.error_message
  end

  test "failed narration triggers refund via explicit RefundsPayment wiring" do
    Mocktail.replace(RefundsPayment)
    stubs { |m| RefundsPayment.call(content: m.any) }.with { nil }

    Mocktail.replace(FetchesJinaContent)
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.failure("Could not fetch URL") }
    stubs { |m| FetchesJinaContent.call(url: m.any) }.with { Result.failure("Jina failed too") }

    ProcessesNarration.call(narration: @narration)

    @narration.reload
    assert_equal "failed", @narration.status

    verify { RefundsPayment.call(content: @narration) }
  end

  # ── Character limit ────────────────────────────────────────────────────

  test "marks narration as failed when content exceeds MPP character limit" do
    long_content = "x" * (AppConfig::Mpp::CHARACTER_LIMIT + 1)
    html = "<article><p>#{long_content}</p></article>"

    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }

    ProcessesNarration.call(narration: @narration)

    @narration.reload
    assert_equal "failed", @narration.status
    assert_includes @narration.error_message, "character limit"
  end

  test "allows content within MPP character limit" do
    stub_successful_fetch
    stub_successful_llm
    stub_successful_audio_synthesis
    stub_cloud_storage

    ProcessesNarration.call(narration: @narration)

    @narration.reload
    assert_equal "complete", @narration.status
  end

  # ── GCS upload ─────────────────────────────────────────────────────────

  test "uploads audio to GCS under narrations scope" do
    stub_successful_fetch
    stub_successful_llm
    stub_successful_audio_synthesis

    mock_gcs = Mocktail.of(CloudStorage)
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| CloudStorage.new(podcast_id: m.any) }.with { mock_gcs }

    ProcessesNarration.call(narration: @narration)

    upload_calls = Mocktail.calls(mock_gcs, :upload_content)
    assert_equal 1, upload_calls.size
    assert_match %r{episodes/.*\.mp3}, upload_calls.first.args.last || upload_calls.first.kwargs[:remote_path]
  end

  # --- TtsUsage recording (agent-team-ff05) ---

  test "records a TtsUsage row with source=actual after successful narration synthesis" do
    stub_successful_fetch
    stub_successful_llm
    stub_successful_audio_synthesis(billed_characters: 4_200)
    stub_cloud_storage

    assert_difference -> { TtsUsage.count }, 1 do
      ProcessesNarration.call(narration: @narration)
    end

    usage = @narration.reload.tts_usage
    assert_not_nil usage
    assert_equal "actual", usage.source
    assert_equal @narration.voice, usage.voice_id
    # narration fixture voice is en-GB-Standard-D → standard tier
    assert_equal "standard", usage.voice_tier
    assert_equal 4_200, usage.character_count
    # 4200 * 400 / 1_000_000 = 1.68 → ceil → 2
    assert_equal 2, usage.cost_cents
  end

  test "TtsUsage character_count matches billed count, NOT source_text.length" do
    text_narration = Narration.create!(
      mpp_payment: MppPayment.create!(amount_cents: 150, currency: "usd", status: :completed, user: users(:one)),
      title: "Text Narration",
      source_type: :text,
      source_text: "Short source.", # 13 chars
      voice: "en-GB-Chirp3-HD-Enceladus",
      expires_at: 24.hours.from_now
    )

    stub_successful_llm
    stub_successful_audio_synthesis(billed_characters: 777)
    stub_cloud_storage

    ProcessesNarration.call(narration: text_narration)

    usage = text_narration.reload.tts_usage
    assert_equal 777, usage.character_count
    assert_not_equal text_narration.source_text.length, usage.character_count
    assert_equal "premium", usage.voice_tier
  end

  test "does not create a TtsUsage row when synthesis fails" do
    stub_successful_fetch
    stub_successful_llm

    mock_synthesizer = Mocktail.of(SynthesizesAudio)
    stubs { |m| mock_synthesizer.call(text: m.any, voice: m.any) }.with { raise StandardError, "TTS API error" }
    stubs { |m| SynthesizesAudio.new(config: m.any) }.with { mock_synthesizer }

    assert_no_difference -> { TtsUsage.count } do
      ProcessesNarration.call(narration: @narration)
    end

    @narration.reload
    assert_equal "failed", @narration.status
  end

  test "cleans up orphaned audio when update fails after upload" do
    stub_successful_fetch
    stub_successful_llm
    stub_successful_audio_synthesis

    mock_gcs = Mocktail.of(CloudStorage)
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| mock_gcs.delete_file(remote_path: m.any) }.with { true }
    stubs { |m| CloudStorage.new(podcast_id: m.any) }.with { mock_gcs }

    # Make the final update fail
    original_update = @narration.method(:update!)
    call_count = 0
    @narration.define_singleton_method(:update!) do |**attrs|
      call_count += 1
      if attrs[:status] == :complete
        raise ActiveRecord::RecordInvalid.new(self)
      end
      original_update.call(**attrs)
    end

    ProcessesNarration.call(narration: @narration)

    delete_calls = Mocktail.calls(mock_gcs, :delete_file)
    assert_equal 1, delete_calls.size
  end

  private

  def stub_successful_fetch
    html = "<article><h1>Real Title</h1><p>Article content here that is long enough to pass the minimum character requirement for extraction. This paragraph contains substantial content to be processed.</p></article>"
    stubs { |m| FetchesUrl.call(url: m.any) }.with { Result.success(html) }
  end

  def stub_successful_llm
    mock_llm_result = Result.success(ProcessesWithLlm::LlmData.new(
      title: "Real Title",
      author: "John Doe",
      description: "A great article.",
      content: "Article content here."
    ))
    stubs { |m| ProcessesWithLlm.call(text: m.any, episode: m.any) }.with { mock_llm_result }
  end

  def stub_successful_audio_synthesis(billed_characters: 0)
    mock_synthesizer = Mocktail.of(SynthesizesAudio)
    stubs { |m| mock_synthesizer.call(text: m.any, voice: m.any) }.with { "fake audio content" }
    stubs { mock_synthesizer.last_billed_characters }.with { billed_characters }
    stubs { |m| SynthesizesAudio.new(config: m.any) }.with { mock_synthesizer }
  end

  def stub_cloud_storage
    mock_gcs = Mocktail.of(CloudStorage)
    stubs { |m| mock_gcs.upload_content(content: m.any, remote_path: m.any) }.with { nil }
    stubs { |m| CloudStorage.new(podcast_id: m.any) }.with { mock_gcs }
  end
end
