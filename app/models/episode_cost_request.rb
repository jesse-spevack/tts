# frozen_string_literal: true

# Immutable input to CalculatesAnticipatedEpisodeCost. Packages the fields
# the service needs so callers stop threading five+ kwargs through every
# cost-calc site:
#
#   user               — the submitting user (for voice resolution)
#   source_type        — "text" | "paste" | "extension" | "email" |
#                        "file" | "upload" | "url"
#   text               — raw text content (when applicable)
#   url                — URL (when source_type == "url"; unused for length)
#   upload             — uploaded file (IO-like with #size) or raw string
#   source_text_length — pre-computed length override; wins over text/upload
#                        extraction. Used by cost-preview (client sends
#                        file.size without the blob) and ProcessesUrlEpisode
#                        (post-extract character_count).
class EpisodeCostRequest
  attr_reader :user, :source_type, :text, :url, :upload, :source_text_length

  def initialize(user:, source_type:, text: nil, url: nil, upload: nil, source_text_length: nil)
    @user = user
    @source_type = source_type.to_s
    @text = text
    @url = url
    @upload = upload
    @source_text_length = source_text_length
    freeze
  end
end
