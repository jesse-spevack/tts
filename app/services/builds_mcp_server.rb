# frozen_string_literal: true

class BuildsMcpServer
  TOOLS = [
    CreateEpisodeFromUrlTool,
    CreateEpisodeFromTextTool,
    ListEpisodesTool,
    GetEpisodeTool,
    DeleteEpisodeTool,
    GetFeedUrlTool,
    ListVoicesTool
  ].freeze

  def self.call(user:)
    MCP::Server.new(
      name: "podread",
      version: "1.0.0",
      instructions: "PodRead converts articles and text into podcast episodes. " \
        "Use these tools to create episodes, check their status, and manage the user's podcast feed.",
      tools: TOOLS,
      server_context: { user: user }
    )
  end
end
