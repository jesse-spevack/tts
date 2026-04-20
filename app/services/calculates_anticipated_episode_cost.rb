# frozen_string_literal: true

# Orchestrates the "how many credits will this episode cost?" computation that
# the web, API v1, and MCP text-tool paths all need before they attempt to
# create an Episode. Composes:
#
#   ResolvesVoice.call(requested_key: nil, user:)       # user's voice tier
#   CalculatesEpisodeCreditCost.call(source_text_length:, voice:)
#
# Callers pass their raw source inputs by keyword (text/url/upload) and a
# `source_type` string describing which input to measure. This service
# handles the branching so controllers don't have to:
#
#   source_type: "text" | "paste"      → text.to_s.length
#   source_type: "extension"           → text.to_s.length   (API v1 treats
#                                        extension content as a text variant)
#   source_type: "file"  | "upload"    → upload.size (if IO-like) else
#                                        upload.to_s.length (raw string)
#   source_type: "url"                 → 1  (URL shortcut — real cost is
#                                        resolved later in ProcessesUrlEpisode)
#   anything else                      → 0
#
# Returns Result.success(Integer) with the 1-or-2 credit cost. Failure only if
# ResolvesVoice fails, which cannot happen when requested_key is nil (stale
# preferences silently fall through to the catalog default).
class CalculatesAnticipatedEpisodeCost
  def self.call(user:, source_type:, text: nil, url: nil, upload: nil)
    new(user: user, source_type: source_type, text: text, url: url, upload: upload).call
  end

  def initialize(user:, source_type:, text:, url:, upload:)
    @user = user
    @source_type = source_type
    @text = text
    @url = url
    @upload = upload
  end

  def call
    voice_result = ResolvesVoice.call(requested_key: nil, user: user)
    return voice_result if voice_result.failure?

    cost = CalculatesEpisodeCreditCost.call(
      source_text_length: source_text_length,
      voice: voice_result.data
    )
    Result.success(cost)
  end

  private

  attr_reader :user, :source_type, :text, :url, :upload

  def source_text_length
    case source_type.to_s
    when "text", "paste", "extension"
      text.to_s.length
    when "file", "upload"
      if upload.respond_to?(:size)
        upload.size
      else
        upload.to_s.length
      end
    when "url"
      1
    else
      0
    end
  end
end
