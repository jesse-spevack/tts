# frozen_string_literal: true

class GetFeedUrlTool < MCP::Tool
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

    MCP::Tool::Response.new([ { type: "text", text: { feed_url: feed_url }.to_json } ])
  end
end
