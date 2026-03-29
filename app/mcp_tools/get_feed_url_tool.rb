# frozen_string_literal: true

class GetFeedUrlTool < MCP::Tool
  extend McpToolHelpers

  tool_name "get_feed_url"
  description "Get the user's podcast RSS feed URL. This URL can be added to any podcast app to listen to episodes."

  input_schema({
    type: "object",
    properties: {}
  })

  def self.call(server_context: nil)
    user = server_context[:user]

    podcast = GetsDefaultPodcastForUser.call(user: user)
    feed_url = GeneratesPodcastFeedUrl.call(podcast)

    success_response({ feed_url: feed_url })
  end
end
