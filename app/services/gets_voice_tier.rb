# frozen_string_literal: true

# Resolves the tier (:premium / :standard) for an episode based on the
# google_voice string stamped on the episode at synth time (or the user's
# current voice as a fallback for legacy rows — see Episode#effective_voice).
#
# Delegates the string → tier lookup to AppConfig::Tts.tier_for, which is
# the canonical catalog-backed resolver (agent-team-s5jo). This wrapper
# adds the episode contract (effective_voice fallback) and the
# symbol-return shape that view/controller callers already depend on.
#
#   - blank effective_voice → :standard (no warn, normal pre-synth path)
#   - effective_voice in Voice::CATALOG → the catalog entry's tier
#   - effective_voice non-blank but missing → AppConfig::Tts.tier_for
#     emits `tts_tier_lookup_missed` and returns "standard"
class GetsVoiceTier
  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
  end

  def call
    AppConfig::Tts.tier_for(@episode.effective_voice).to_sym
  end
end
