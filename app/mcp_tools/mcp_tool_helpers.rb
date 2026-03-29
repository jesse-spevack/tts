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

  def check_creation_prerequisites(user:, voice: nil)
    permission = ChecksEpisodeCreationPermission.call(user: user)
    unless permission.success?
      return error_response("tier_limit", "You've used all your free episodes this month. Upgrade at #{AppConfig::Domain::BASE_URL}/upgrade")
    end

    rate_limit = ChecksEpisodeRateLimit.call(user: user)
    unless rate_limit.success?
      return error_response("rate_limited", rate_limit.error)
    end

    if voice.present?
      unless user.available_voices.include?(voice)
        return error_response("invalid_voice", "Unknown voice '#{voice}'. Use list_voices to see available options.")
      end
    end

    nil
  end

  def record_successful_creation(user:, episode:)
    RecordsEpisodeUsage.call(user: user)
    DeductsCredit.call(user: user, episode: episode) if user.credit_user?
  end
end
