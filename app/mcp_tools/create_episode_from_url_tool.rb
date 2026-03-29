# frozen_string_literal: true

class CreateEpisodeFromUrlTool < MCP::Tool
  extend McpToolHelpers

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

    if (error = check_creation_prerequisites(user: user, voice: voice))
      return error
    end

    podcast = GetsDefaultPodcastForUser.call(user: user)
    result = CreatesUrlEpisode.call(podcast: podcast, user: user, url: url)

    if result.success?
      record_successful_creation(user: user, episode: result.data)
      success_response({ id: result.data.prefix_id, status: "processing" })
    else
      error_response("creation_failed", result.error)
    end
  end
end
