# frozen_string_literal: true

# Resolves the tier ("premium" / "standard") for a Google voice string,
# backed by Voice::CATALOG. Unknown voice_ids log a drift warning and
# fall back to "standard" (conservative accounting).
class GetsVoiceTier
  def self.call(episode:)
    tier_for(episode.effective_voice).to_sym
  end

  def self.tier_for(google_voice_id)
    tier = tier_by_google_voice[google_voice_id]
    return tier.to_s if tier

    Rails.logger.warn "event=tts_tier_lookup_missed google_voice=#{google_voice_id}"
    "standard"
  end

  def self.tier_by_google_voice
    @tier_by_google_voice ||= Voice::CATALOG.each_key.each_with_object({}) do |key, h|
      entry = Voice.find(key)
      h[entry.google_voice] = entry.tier if entry
    end.freeze
  end
end
