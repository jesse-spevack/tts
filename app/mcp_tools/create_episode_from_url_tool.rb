# frozen_string_literal: true

class CreateEpisodeFromUrlTool < MCP::Tool
  tool_name "create_episode_from_url"
  description "Create a podcast episode from a URL. The article will be fetched, converted to audio, and added to the user's podcast feed."

  input_schema({
    type: "object",
    properties: {
      url: { type: "string", description: "The URL of the article to convert to a podcast episode" },
      voice: { type: "string", description: "Voice ID to use (from list_voices). Falls back to user's default voice if omitted." }
    },
    required: [ "url" ]
  })

  def self.call(url:, voice: nil, server_context: nil)
    user = server_context[:user]

    permission = ChecksEpisodeCreationPermission.call(user: user)
    unless permission.success?
      return error_response("tier_limit", "You've used all your free episodes this month. Upgrade at #{AppConfig::Domain::BASE_URL}/upgrade")
    end

    rate_limit = ChecksEpisodeRateLimit.call(user: user)
    unless rate_limit.success?
      return error_response("rate_limited", rate_limit.error)
    end

    if voice.present?
      available = user.available_voices
      unless available.include?(voice)
        return error_response("invalid_voice", "Unknown voice '#{voice}'. Use list_voices to see available options.")
      end
    end

    podcast = GetsDefaultPodcastForUser.call(user: user)
    result = CreatesUrlEpisode.call(podcast: podcast, user: user, url: url)

    if result.success?
      RecordsEpisodeUsage.call(user: user)
      DeductsCredit.call(user: user, episode: result.data) if user.credit_user?

      success_response({ id: result.data.prefix_id, status: "processing" })
    else
      error_response("creation_failed", result.error)
    end
  end

  private

  def self.success_response(data)
    MCP::Tool::Response.new([ { type: "text", text: data.to_json } ])
  end

  def self.error_response(error_type, message)
    MCP::Tool::Response.new(
      [ { type: "text", text: { error: error_type, message: message }.to_json } ],
      error: true
    )
  end
end
