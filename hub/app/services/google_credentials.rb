require "base64"
require "json"

module GoogleCredentials
  def self.from_env
    unless ENV["KAMAL_REGISTRY_PASSWORD"].present?
      raise "KAMAL_REGISTRY_PASSWORD not set"
    end

    decoded = Base64.decode64(ENV["KAMAL_REGISTRY_PASSWORD"])
    JSON.parse(decoded)
  rescue ArgumentError => e
    raise "Failed to decode KAMAL_REGISTRY_PASSWORD as base64: #{e.message}"
  rescue JSON::ParserError => e
    raise "Failed to parse KAMAL_REGISTRY_PASSWORD as JSON: #{e.message}"
  end
end
