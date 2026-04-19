# frozen_string_literal: true

# Resolves the Voice for a narration-creating request based on the MPP v1
# hierarchy (agent-team-nkz):
#
#   1. If a valid voice key is explicitly requested → use it
#   2. Else if an authenticated user has a saved voice_preference → use that
#   3. Else → catalog default (Voice::DEFAULT_KEY)
#
# Anonymous callers skip step 2. A requested-but-invalid voice key is a hard
# error (Result.failure(:invalid_voice)) — the caller should surface 422, not
# silently fall through to a default.
#
# Usage:
#
#   result = ResolvesVoice.call(
#     requested_key: params[:voice],
#     user:          Current.user   # may be nil for anonymous flows
#   )
#   return render_422 if result.failure?
#   voice = result.data  # => Voice::Entry — has .tier, .price_cents, etc.
class ResolvesVoice
  def self.call(requested_key:, user: nil)
    new(requested_key: requested_key, user: user).call
  end

  def initialize(requested_key:, user:)
    @requested_key = requested_key
    @user = user
  end

  def call
    if @requested_key.present?
      voice = Voice.find(@requested_key)
      return Result.failure(:invalid_voice) if voice.nil?
      return Result.success(voice)
    end

    if @user&.voice_preference.present?
      voice = Voice.find(@user.voice_preference)
      # Stale preferences (user picked a voice that's since been removed)
      # silently fall through to the catalog default rather than 422ing a
      # caller who did nothing wrong.
      return Result.success(voice) if voice
    end

    Result.success(Voice.find(Voice::DEFAULT_KEY))
  end
end
