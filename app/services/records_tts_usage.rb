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
    voice_tier = AppConfig::Tts.tier_for(@voice_id)
    cost_cents = ComputesTtsCost.call(voice_tier: voice_tier, character_count: @character_count)

    usage = TtsUsage.create!(
      usable: @usable,
      provider: @provider,
      voice_id: @voice_id,
      voice_tier: voice_tier,
      character_count: @character_count,
      cost_cents: cost_cents,
      source: @source
    )

    log_info "tts_usage_recorded",
             tts_usage_id: usage.id,
             usable_type: @usable.class.name,
             usable_id: @usable.id,
             voice_id: @voice_id,
             voice_tier: voice_tier,
             character_count: @character_count,
             cost_cents: cost_cents,
             source: @source

    usage
  end
end
