# frozen_string_literal: true

# Orchestrates the "how many credits will this episode cost?" computation that
# the web, API v1, MCP text-tool, email-ingest, cost-preview, and URL-async
# paths all need. Composes:
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
#   source_type: "email"               → text.to_s.length   (email-ingest
#                                        content is a text variant)
#   source_type: "file"  | "upload"    → upload.size (if IO-like) else
#                                        upload.to_s.length (raw string)
#   source_type: "url"                 → nil (deferred — real article length
#                                        isn't known until FetchesArticleContent
#                                        runs inside ProcessesUrlEpisode)
#   anything else                      → 0
#
# Callers who already know the content length (e.g. the web cost-preview
# endpoint sending pre-computed `upload_length`, or ProcessesUrlEpisode
# after fetch+extract knows the article's character_count) can pass
# `source_text_length:` directly. When present, it wins over source_type-based
# extraction — so passing `source_type: "url", source_text_length: N`
# computes the real cost rather than returning nil.
#
# Returns Result.success(Integer) when a cost can be computed, or
# Result.success(nil) for the deferred-URL case. Callers explicitly handle
# nil (see ChecksEpisodeCreationPermission#check_credit_balance and
# DebitsEpisodeCredit's episode.url? short-circuit). Failure only if
# ResolvesVoice fails, which cannot happen when requested_key is nil (stale
# preferences silently fall through to the catalog default).
class CalculatesAnticipatedEpisodeCost
  def self.call(user:, source_type:, text: nil, url: nil, upload: nil, source_text_length: nil)
    new(
      user: user,
      source_type: source_type,
      text: text,
      url: url,
      upload: upload,
      source_text_length: source_text_length
    ).call
  end

  def initialize(user:, source_type:, text:, url:, upload:, source_text_length:)
    @user = user
    @source_type = source_type
    @text = text
    @url = url
    @upload = upload
    @override_length = source_text_length
  end

  def call
    voice_result = ResolvesVoice.call(requested_key: nil, user: user)
    return voice_result if voice_result.failure?

    length = source_text_length
    return Result.success(nil) if length.nil?

    cost = CalculatesEpisodeCreditCost.call(
      source_text_length: length,
      voice: voice_result.data
    )
    Result.success(cost)
  end

  private

  attr_reader :user, :source_type, :text, :url, :upload, :override_length

  def source_text_length
    return override_length.to_i unless override_length.nil?

    case source_type.to_s
    when "text", "paste", "extension", "email"
      text.to_s.length
    when "file", "upload"
      if upload.respond_to?(:size)
        upload.size
      else
        upload.to_s.length
      end
    when "url"
      nil
    else
      0
    end
  end
end
