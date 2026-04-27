# frozen_string_literal: true

require "test_helper"

class RecordsTtsUsageTest < ActiveSupport::TestCase
  test "creates TtsUsage row with source=actual by default" do
    episode = episodes(:one)

    assert_difference -> { TtsUsage.count }, 1 do
      RecordsTtsUsage.call(
        usable: episode,
        voice_id: "en-GB-Standard-D",
        character_count: 1_500
      )
    end

    usage = TtsUsage.last
    assert_equal episode, usage.usable
    assert_equal "google", usage.provider
    assert_equal "en-GB-Standard-D", usage.voice_id
    assert_equal "standard", usage.voice_tier
    assert_equal 1_500, usage.character_count
    assert_equal "actual", usage.source
  end

  test "infers premium tier from Chirp3-HD voice id" do
    narration = narrations(:one)

    RecordsTtsUsage.call(
      usable: narration,
      voice_id: "en-GB-Chirp3-HD-Enceladus",
      character_count: 2_000
    )

    usage = TtsUsage.last
    assert_equal "premium", usage.voice_tier
  end

  test "computes cost_cents via ComputesTtsCost helper" do
    episode = episodes(:one)

    RecordsTtsUsage.call(
      usable: episode,
      voice_id: "en-US-Chirp3-HD-Callirrhoe",
      character_count: 1_000
    )

    usage = TtsUsage.last
    # premium @ 1000 chars: 1000 * 3000 / 1_000_000 = 3
    assert_equal 3, usage.cost_cents
  end

  test "standard tier 2501 chars ceils to 2 cents" do
    episode = episodes(:one)

    RecordsTtsUsage.call(
      usable: episode,
      voice_id: "en-GB-Standard-D",
      character_count: 2_501
    )

    assert_equal 2, TtsUsage.last.cost_cents
  end

  test "accepts explicit source override for future backfills" do
    episode = episodes(:one)

    RecordsTtsUsage.call(
      usable: episode,
      voice_id: "en-GB-Standard-D",
      character_count: 1_000,
      source: "estimate"
    )

    assert_equal "estimate", TtsUsage.last.source
  end

  test "returns the created usage record" do
    episode = episodes(:one)

    result = RecordsTtsUsage.call(
      usable: episode,
      voice_id: "en-GB-Standard-D",
      character_count: 500
    )

    assert_instance_of TtsUsage, result
    assert_equal episode, result.usable
  end

  # --- idempotency on retry (agent-team-ete2) ---
  #
  # GeneratesEpisodeAudio#call records usage after a successful synth, then
  # continues with GCS upload / duration / feed upload. Any of those can
  # raise a TransientAudioErrors::TRANSIENT_ERRORS which triggers a job
  # retry. The retry re-invokes the entire service, including a second
  # RecordsTtsUsage.call for the same usable. The (usable_type, usable_id)
  # unique index must not turn that retry into a RecordNotUnique.

  test "second call for the same usable does not raise and does not create a duplicate" do
    episode = episodes(:one)

    assert_difference -> { TtsUsage.count }, 1 do
      2.times do
        RecordsTtsUsage.call(
          usable: episode,
          voice_id: "en-GB-Standard-D",
          character_count: 1_000
        )
      end
    end
  end

  test "second call overwrites the first with the later (authoritative) billed figures" do
    # Chunk-level failures between retries can shift the billed character
    # count — the latest successful synth is the truth.
    episode = episodes(:one)

    RecordsTtsUsage.call(
      usable: episode,
      voice_id: "en-GB-Standard-D",
      character_count: 1_000
    )
    RecordsTtsUsage.call(
      usable: episode,
      voice_id: "en-GB-Chirp3-HD-Enceladus",
      character_count: 2_000
    )

    usage = TtsUsage.find_by!(usable: episode)
    assert_equal "en-GB-Chirp3-HD-Enceladus", usage.voice_id
    assert_equal "premium", usage.voice_tier
    assert_equal 2_000, usage.character_count
    # premium @ 2000 chars: 2000 * 3000 / 1_000_000 = 6
    assert_equal 6, usage.cost_cents
  end
end
