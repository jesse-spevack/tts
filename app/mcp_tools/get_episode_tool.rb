# frozen_string_literal: true

class GetEpisodeTool < MCP::Tool
  tool_name "get_episode"
  description "Get details about a specific episode, including its processing status."

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

    data = {
      id: episode.prefix_id,
      title: episode.title,
      author: episode.author,
      description: episode.description,
      status: episode.status,
      source_type: episode.source_type,
      source_url: episode.source_url,
      duration_seconds: episode.duration_seconds,
      error_message: episode.error_message,
      created_at: episode.created_at.iso8601
    }

    MCP::Tool::Response.new([ { type: "text", text: data.to_json } ])
  end
end
