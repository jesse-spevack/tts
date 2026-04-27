# frozen_string_literal: true

# Maps (voice_tier, character_count) → integer cost in cents.
#
# Rates live in AppConfig::Tts::COST_CENTS_PER_MILLION and reflect Google
# Cloud TTS COGS:
#   - standard: $4  per 1M chars → 400¢ / 1_000_000
#   - premium:  $30 per 1M chars → 3000¢ / 1_000_000
#
# Rounding: ceil. Internal cost tracking should never under-bill ourselves;
# a sub-cent rounding bias in our favor is harmless. See agent-team-ff05.
class ComputesTtsCost
  UNKNOWN_TIER_ERROR = "unknown voice_tier: %s"

  def self.call(voice_tier:, character_count:)
    new(voice_tier: voice_tier, character_count: character_count).call
  end

  def initialize(voice_tier:, character_count:)
    @voice_tier = voice_tier.to_s
    @character_count = character_count.to_i
  end

  def call
    rate = AppConfig::Tts::COST_CENTS_PER_MILLION[@voice_tier]
    raise ArgumentError, format(UNKNOWN_TIER_ERROR, @voice_tier) if rate.nil?

    return 0 if @character_count <= 0

    (@character_count * rate.to_r / 1_000_000).ceil
  end
end
