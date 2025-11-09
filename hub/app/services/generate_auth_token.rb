class GenerateAuthToken
  TOKEN_EXPIRATION = 30.minutes

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    @user.update!(
      auth_token: SecureRandom.urlsafe_base64,
      auth_token_expires_at: TOKEN_EXPIRATION.from_now
    )
  end
end
