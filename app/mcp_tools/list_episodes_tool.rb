# frozen_string_literal: true

class ListEpisodesTool < MCP::Tool
  extend McpToolHelpers

  tool_name "list_episodes"
  description "List the user's podcast episodes, newest first. Supports pagination."

  input_schema({
    type: "object",
    properties: {
      page: { type: "integer", description: "Page number (default: 1)", minimum: 1 },
      limit: { type: "integer", description: "Episodes per page (default: 20, max: 100)", minimum: 1, maximum: 100 }
    }
  })

  def self.call(page: 1, limit: 20, server_context: nil)
    user = server_context[:user]

    page = [ page.to_i, 1 ].max
    limit = [ [ limit.to_i, 1 ].max, AppConfig::Api::MAX_PER_PAGE ].min

    episodes = user.episodes.newest_first
    total = episodes.count
    episodes = episodes.offset((page - 1) * limit).limit(limit)

    success_response({
      episodes: episodes.map { |ep| serialize_episode(ep) },
      meta: { page: page, limit: limit, total: total }
    })
  end

  private

  def self.serialize_episode(episode)
    {
      id: episode.prefix_id,
      title: episode.title,
      author: episode.author,
      status: episode.status,
      source_type: episode.source_type,
      source_url: episode.source_url,
      duration_seconds: episode.duration_seconds,
      created_at: episode.created_at.iso8601
    }
  end
end
