# frozen_string_literal: true

# Persists a TtsUsage row for a successful Google TTS synthesis.
#
# The character_count comes from the actual text sent to Google (summed
# across successful chunks) — NOT source_text.length. Retries, wrapping,
# chunking, and chunk failures all cause drift between source text and
# what Google actually billed us for.
class RecordsTtsUsage
  include StructuredLogging

  def self.call(usable:, voice_id:, character_count:, provider: "google", source: "actual")
    new(
      usable: usable,
      voice_id: voice_id,
      character_count: character_count,
      provider: provider,
      source: source
    ).call
  end

  def initialize(usable:, voice_id:, character_count:, provider:, source:)
    @usable = usable
    @voice_id = voice_id
    @character_count = character_count
    @provider = provider
    @source = source
  end

  def call
    voice_tier = GetsVoiceTier.tier_for(@voice_id)
    cost_cents = ComputesTtsCost.call(voice_tier: voice_tier, character_count: @character_count)

    # Idempotent on retry: GeneratesEpisodeAudio can re-enter after a
    # transient upload failure, so let the latest synth's figures win
    # instead of colliding on the unique (usable_type, usable_id) index.
    usage = TtsUsage.find_or_initialize_by(usable: @usable)
    was_new = usage.new_record?
    usage.assign_attributes(
      provider: @provider,
      voice_id: @voice_id,
      voice_tier: voice_tier,
      character_count: @character_count,
      cost_cents: cost_cents,
      source: @source
    )
    usage.save!

    log_info "tts_usage_recorded",
             tts_usage_id: usage.id,
             usable_type: @usable.class.name,
             usable_id: @usable.id,
             voice_id: @voice_id,
             voice_tier: voice_tier,
             character_count: @character_count,
             cost_cents: cost_cents,
             source: @source,
             action: was_new ? "created" : "updated"

    usage
  end
end
