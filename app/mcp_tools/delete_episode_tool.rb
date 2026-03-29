# frozen_string_literal: true

class DeleteEpisodeTool < MCP::Tool
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

    unless episode
      return MCP::Tool::Response.new(
        [ { type: "text", text: { error: "not_found", message: "Episode not found" }.to_json } ],
        error: true
      )
    end

    DeleteEpisodeJob.perform_later(episode_id: episode.id)

    MCP::Tool::Response.new([ { type: "text", text: { deleted: true }.to_json } ])
  end
end
