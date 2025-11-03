# Podcast ID format validation utilities
#
# Podcast IDs must follow the format: podcast_{16 hex chars}
# Example: podcast_a1b2c3d4e5f6a7b8
module PodcastIdValidator
  # Regex pattern for valid podcast_id format
  FORMAT = /^podcast_[a-f0-9]{16}$/

  # Error message for invalid format
  ERROR_MESSAGE = "Invalid podcast_id format. " \
                  "Expected format: podcast_{16 hex chars} (e.g., podcast_a1b2c3d4e5f6a7b8). " \
                  "Generate with: openssl rand -hex 8".freeze

  # Validate podcast_id format
  # @param podcast_id [String] The podcast ID to validate
  # @raise [ArgumentError] If format is invalid
  def self.validate!(podcast_id)
    return if podcast_id&.match?(FORMAT)

    raise ArgumentError, "#{ERROR_MESSAGE}. Got: '#{podcast_id}'"
  end

  # Check if podcast_id format is valid
  # @param podcast_id [String] The podcast ID to check
  # @return [Boolean] True if valid, false otherwise
  def self.valid?(podcast_id)
    !podcast_id.nil? && podcast_id.match?(FORMAT)
  end
end
