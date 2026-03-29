# frozen_string_literal: true

class ListVoicesTool < MCP::Tool
  extend McpToolHelpers

  tool_name "list_voices"
  description "List available voices for podcast episodes. Results are filtered by the user's subscription tier. To change your default voice, visit Settings at podread.app/settings."

  input_schema({
    type: "object",
    properties: {}
  })

  def self.call(server_context: nil)
    user = server_context[:user]

    available_keys = user.available_voices
    voices = available_keys.filter_map do |key|
      voice = Voice.find(key)
      next unless voice

      {
        id: voice.key,
        name: voice.name,
        accent: voice.accent,
        gender: voice.gender
      }
    end

    success_response({ voices: voices })
  end
end
