# frozen_string_literal: true

class RegeneratesEmailIngestToken
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    @user.update!(email_ingest_token: generate_token)
  end

  private

  def generate_token
    SecureRandom.urlsafe_base64(16).downcase
  end
end
