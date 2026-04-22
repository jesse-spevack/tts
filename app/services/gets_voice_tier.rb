# frozen_string_literal: true

# Resolves the tier (:premium / :standard) for an episode based on the
# google_voice string stamped on the episode at synth time (or the user's
# current voice as a fallback for legacy rows — see Episode#effective_voice).
#
#   - blank effective_voice → :standard (no warn, normal pre-synth path)
#   - effective_voice in catalog → the catalog entry's tier
#   - effective_voice non-blank but missing from catalog → warn + :standard
#
# A catalog miss is a drift/rename signal worth surfacing, since the
# alternative would silently mislabel a premium voice as Standard.
class GetsVoiceTier
  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
  end

  def call
    return :standard if google_voice.blank?

    self.class.tier_by_google_voice[google_voice] || warn_and_default
  end

  # Memoized reverse index: google_voice string → tier symbol. Built once
  # from Voice::CATALOG and frozen. In dev mode Rails reloads constants so
  # the memo resets with the catalog.
  def self.tier_by_google_voice
    @tier_by_google_voice ||= Voice::CATALOG.each_with_object({}) do |(key, _data), h|
      entry = Voice.find(key)
      h[entry.google_voice] = entry.tier if entry
    end.freeze
  end

  private

  def google_voice
    @google_voice ||= @episode.effective_voice
  end

  def warn_and_default
    Rails.logger.warn "event=voice_tier_lookup_missed google_voice=#{google_voice}"
    :standard
  end
end
