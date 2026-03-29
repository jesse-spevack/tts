# frozen_string_literal: true

class ListVoicesTool < MCP::Tool
  tool_name "list_voices"
  description "List available voices for podcast episodes. Results are filtered by the user's subscription tier."

  input_schema({
    type: "object",
    properties: {}
  })

  def self.call(server_context: nil)
    user = server_context[:user]

    available_keys = user.available_voices
    voices = available_keys.map do |key|
      voice = Voice.find(key)
      next unless voice

      {
        id: voice.key,
        name: voice.name,
        accent: voice.accent,
        gender: voice.gender
      }
    end.compact

    MCP::Tool::Response.new([ { type: "text", text: { voices: voices }.to_json } ])
  end
end
