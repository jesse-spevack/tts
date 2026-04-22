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
# Interface (7 methods):
#   source_text, voice, provider, status, tts_usage, mpp_payment, cost
#
# status / tts_usage / mpp_payment come from the including model (enum +
# associations); the concern provides source_text/provider defaults
# and the cost method below.
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

  # Value object — NOT persisted. Column promotion deferred to agent-team-0rwa.
  def cost
    tts_usage&.cost_cents || 0
  end
end
