# frozen_string_literal: true

class FindsApiToken
  def self.call(plain_token:)
    new(plain_token: plain_token).call
  end

  def initialize(plain_token:)
    @plain_token = plain_token
  end

  def call
    return nil if @plain_token.blank?

    digest = hash_token(@plain_token)
    ApiToken.active.find_by(token_digest: digest)
  end

  private

  def hash_token(plain_token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, plain_token)
  end
end
