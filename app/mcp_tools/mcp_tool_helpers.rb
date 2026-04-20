# frozen_string_literal: true

module McpToolHelpers
  def success_response(data)
    MCP::Tool::Response.new([ { type: "text", text: data.to_json } ])
  end

  def error_response(error_type, message)
    MCP::Tool::Response.new(
      [ { type: "text", text: { error: error_type, message: message }.to_json } ],
      error: true
    )
  end

  # Pre-flight gate: free-quota / credit-balance / rate-limit check that
  # runs BEFORE CreatesPasteEpisode or CreatesUrlEpisode. Callers that know
  # the anticipated credit cost (paste/text tool has the text in hand) must
  # pass it so ChecksEpisodeCreationPermission rejects before an Episode is
  # written. Otherwise DeductsCredit silently fails post-create, leaving
  # orphan episodes.
  def check_creation_prerequisites(user:, anticipated_cost: nil)
    permission = ChecksEpisodeCreationPermission.call(user: user, anticipated_cost: anticipated_cost)
    unless permission.success?
      return error_response(mcp_error_type(permission), mcp_error_message(permission))
    end

    rate_limit = ChecksEpisodeRateLimit.call(user: user)
    unless rate_limit.success?
      return error_response("rate_limited", rate_limit.error)
    end

    nil
  end

  def record_successful_creation(user:, episode:)
    RecordsEpisodeUsage.call(user: user)
    return if user.complimentary? || user.unlimited?

    cost = CalculatesEpisodeCreditCost.call(
      source_text_length: episode.source_text.to_s.length,
      voice: Voice.find(user.voice_preference) || Voice.find(Voice::DEFAULT_KEY)
    )
    DeductsCredit.call(user: user, episode: episode, cost_in_credits: cost)
  end

  private

  def mcp_error_type(result)
    case result.code
    when :insufficient_credits then "insufficient_credits"
    else "tier_limit"
    end
  end

  def mcp_error_message(result)
    case result.code
    when :insufficient_credits
      "Not enough credits for this episode. Buy more at #{AppConfig::Domain::BASE_URL}/billing"
    else
      "You've used all your free episodes this month. Upgrade at #{AppConfig::Domain::BASE_URL}/upgrade"
    end
  end
end
