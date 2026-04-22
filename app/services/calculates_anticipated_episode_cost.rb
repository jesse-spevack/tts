# frozen_string_literal: true

# Orchestrates the "how many credits will this episode cost?" computation that
# the web, API v1, MCP text-tool, email-ingest, cost-preview, and URL-async
# paths all need. Composes:
#
#   ResolvesVoice.call(requested_key: nil, user:)       # user's voice tier
#   CalculatesEpisodeCreditCost.call(source_text_length:, voice:)
#
# Callers build an EpisodeCostRequest (carrying user, source_type, and any of
# text/url/upload/source_text_length) and pass it in. This service handles
# the source_type branching so callers don't have to:
#
#   source_type: "text" | "paste"      → text.to_s.length
#   source_type: "extension"           → text.to_s.length   (API v1 treats
#                                        extension content as a text variant)
#   source_type: "email"               → text.to_s.length   (email-ingest
#                                        content is a text variant)
#   source_type: "file"  | "upload"    → upload.size (if IO-like) else
#                                        upload.to_s.length (raw string)
#   source_type: "url"                 → Cost.deferred (real length isn't
#                                        known until FetchesArticleContent
#                                        runs inside ProcessesUrlEpisode)
#   anything else                      → Cost.credits(computed-for-0-chars)
#
# Callers who already know the content length (cost-preview with pre-computed
# upload_length, or ProcessesUrlEpisode after extract knows character_count)
# set `source_text_length` on the request. When present, it wins over
# source_type-based extraction — so a url request with source_text_length
# computes a known cost rather than returning Cost.deferred.
#
# Returns Result.success(Cost). Failure only if ResolvesVoice fails, which
# cannot happen when requested_key is nil (stale preferences silently fall
# through to the catalog default).
class CalculatesAnticipatedEpisodeCost
  def self.call(request)
    new(request).call
  end

  def initialize(request)
    @request = request
  end

  def call
    voice_result = ResolvesVoice.call(requested_key: nil, user: request.user)
    return voice_result if voice_result.failure?

    length = resolved_length
    return Result.success(Cost.deferred) if length.nil?

    credits = CalculatesEpisodeCreditCost.call(
      source_text_length: length,
      voice: voice_result.data
    )
    Result.success(Cost.credits(credits))
  end

  private

  attr_reader :request

  def resolved_length
    return request.source_text_length.to_i unless request.source_text_length.nil?

    case request.source_type
    when "text", "paste", "extension", "email"
      request.text.to_s.length
    when "file", "upload"
      if request.upload.respond_to?(:size)
        request.upload.size
      else
        request.upload.to_s.length
      end
    when "url"
      nil
    else
      0
    end
  end
end
