# frozen_string_literal: true

class CreateEpisodeFromTextTool < MCP::Tool
  extend McpToolHelpers

  tool_name "create_episode_from_text"
  description "Create a podcast episode from text content. The text will be converted to audio using your default voice and added to your podcast feed."

  input_schema({
    type: "object",
    properties: {
      text: { type: "string", description: "The text content to convert to a podcast episode" },
      title: { type: "string", description: "Title for the episode" },
      author: { type: "string", description: "Author of the content (optional)" }
    },
    required: [ "text", "title" ]
  })

  def self.call(text:, title:, author: nil, server_context: nil)
    user = server_context[:user]

    if (error = check_creation_prerequisites(user: user))
      return error
    end

    podcast = GetsDefaultPodcastForUser.call(user: user)
    result = CreatesPasteEpisode.call(
      podcast: podcast,
      user: user,
      text: text,
      title: title,
      author: author
    )

    if result.success?
      record_successful_creation(user: user, episode: result.data)
      success_response({ id: result.data.prefix_id, status: "processing" })
    else
      error_response("creation_failed", result.error)
    end
  end
end
