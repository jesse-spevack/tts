# frozen_string_literal: true

# Facade that consolidates the "create an episode" choreography used by both
# the HTML (EpisodesController) and API v1 (Api::V1::EpisodesController)
# create actions. Both previously hand-rolled the same two-step dance:
#
#   1. Dispatch to the per-source creator (Creates{Url,Paste,File,Extension}Episode)
#      based on the submission's source type.
#   2. On success, run post-create side effects: RecordsEpisodeUsage then
#      DebitsEpisodeCredit.
#
# Callers normalize their HTTP-shaped request into a normalized source_type
# ("url" / "text" / "file" / "extension") and a params hash, and provide the
# already-computed anticipated cost. Param-shape detection (which field is
# present in the request) stays in the controller — that's an HTTP concern.
#
# Order of side effects is load-bearing: usage is recorded BEFORE the credit
# debit. Do not reorder without reading the history on both controllers.
class CreatesEpisode
  SOURCE_TEXT = "text"
  SOURCE_URL = "url"
  SOURCE_FILE = "file"
  SOURCE_EXTENSION = "extension"

  def self.call(user:, podcast:, source_type:, params:, cost_in_credits:)
    new(
      user: user,
      podcast: podcast,
      source_type: source_type,
      params: params,
      cost_in_credits: cost_in_credits
    ).call
  end

  def initialize(user:, podcast:, source_type:, params:, cost_in_credits:)
    @user = user
    @podcast = podcast
    @source_type = source_type
    @params = params
    @cost_in_credits = cost_in_credits
  end

  def call
    result = dispatch
    return result if result.failure?

    RecordsEpisodeUsage.call(user: user)
    DebitsEpisodeCredit.call(user: user, episode: result.data, cost_in_credits: cost_in_credits)

    result
  end

  private

  attr_reader :user, :podcast, :source_type, :params, :cost_in_credits

  def dispatch
    case source_type
    when SOURCE_URL
      CreatesUrlEpisode.call(
        podcast: podcast,
        user: user,
        url: params[:url]
      )
    when SOURCE_TEXT
      CreatesPasteEpisode.call(
        podcast: podcast,
        user: user,
        text: params[:text],
        title: params[:title],
        author: params[:author],
        source_url: params[:source_url]
      )
    when SOURCE_FILE
      CreatesFileEpisode.call(
        podcast: podcast,
        user: user,
        title: params[:title],
        author: params[:author],
        description: params[:description],
        content: params[:content]
      )
    when SOURCE_EXTENSION
      CreatesExtensionEpisode.call(
        podcast: podcast,
        user: user,
        title: params[:title],
        content: params[:content],
        url: params[:url],
        author: params[:author],
        description: params[:description]
      )
    else
      Result.failure("Unknown source_type: #{source_type.inspect}")
    end
  end
end
