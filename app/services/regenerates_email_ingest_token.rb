# frozen_string_literal: true

class RegeneratesEmailIngestToken
  include GeneratesEmailIngestToken

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    @user.update!(email_ingest_token: generate_email_ingest_token)
  end
end
