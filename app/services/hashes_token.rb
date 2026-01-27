# frozen_string_literal: true

class HashesToken
  def self.call(plain_token:)
    new(plain_token: plain_token).call
  end

  def initialize(plain_token:)
    @plain_token = plain_token
  end

  def call
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, @plain_token)
  end
end
