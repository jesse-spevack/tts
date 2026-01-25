# frozen_string_literal: true

class RevokesApiToken
  include StructuredLogging

  def self.call(token:)
    new(token: token).call
  end

  def initialize(token:)
    @token = token
  end

  def call
    @token.revoke!

    log_info "api_token_revoked", user_id: @token.user_id, token_id: @token.id

    @token
  end
end
