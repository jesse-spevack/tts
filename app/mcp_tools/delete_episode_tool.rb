# frozen_string_literal: true

class DeleteEpisodeTool < MCP::Tool
  extend McpToolHelpers

  tool_name "delete_episode"
  description "Delete a podcast episode. The episode will be removed from the feed."

  input_schema({
    type: "object",
    properties: {
      id: { type: "string", description: "Episode ID (e.g. ep_abc123)" }
    },
    required: [ "id" ]
  })

  def self.call(id:, server_context: nil)
    user = server_context[:user]

    episode = user.episodes.find_by_prefix_id(id)
    return error_response("not_found", "Episode not found") unless episode

    DeleteEpisodeJob.perform_later(episode_id: episode.id)

    success_response({ deleted: true })
  end
end
