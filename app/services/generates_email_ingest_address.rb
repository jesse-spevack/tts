# frozen_string_literal: true

class GeneratesEmailIngestAddress
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return nil unless @user.email_episodes_enabled?

    "readtome+#{@user.email_ingest_token}@tts.verynormal.dev"
  end
end
