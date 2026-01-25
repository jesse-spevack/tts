# frozen_string_literal: true

class GetsApiToken
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    @user.api_tokens.active.first
  end
end
