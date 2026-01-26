# frozen_string_literal: true

class DisablesEmailEpisodes
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    @user.update!(
      email_episodes_enabled: false,
      email_ingest_token: nil
    )
  end
end
