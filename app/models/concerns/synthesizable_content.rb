# frozen_string_literal: true

# Shared contract for content types that flow through the synthesis pipeline.
# Mixed into Episode and Narration. The interface is intentionally small —
# callers (ProcessesMppRequest, RefundsPayment, GeneratesEpisodeAudio, etc.)
# duck-type against these methods and nothing more.
#
# Hard no-go list (epic agent-team-sird): no HTTP / auth / mailer /
# publishing / routing symbols. Enforced by
# code_quality:synthesizable_content_purity.
#
# Interface (9 methods):
#   source_text, voice, provider, status, tts_usage, mpp_payment,
#   succeed!(audio_blob:, duration:), fail!(reason:), cost
#
# status / tts_usage / mpp_payment come from the including model (enum +
# associations); the concern provides source_text/provider defaults
# and the lifecycle + cost methods below.
#
# `voice` is defined by each including model — Episode delegates to
# user.voice, Narration has its own column with a before_validation
# default. The concern deliberately does NOT provide a `voice` fallback:
# any user-level fallback would pull User into the concern, which the
# epic's no-go list forbids (no user/auth/ownership in the concern).
module SynthesizableContent
  extend ActiveSupport::Concern

  def source_text
    self[:source_text]
  end

  def provider
    tts_usage&.provider || "google"
  end

  def succeed!(audio_blob:, duration:)
    update!(
      status: :complete,
      audio_size_bytes: audio_blob.bytesize,
      duration_seconds: duration,
      processing_completed_at: Time.current
    )
  end

  def fail!(reason:)
    update!(status: :failed, error_message: reason)
  end

  # Value object — NOT persisted in brick 2b. Brick 3 (agent-team-7i24)
  # replaces this with a persisted cost_cents column.
  def cost
    tts_usage&.cost_cents || 0
  end
end
