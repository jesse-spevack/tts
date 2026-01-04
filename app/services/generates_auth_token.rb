class GeneratesAuthToken
  TOKEN_EXPIRATION = 30.minutes

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    raw_token = SecureRandom.urlsafe_base64
    hashed_token = BCrypt::Password.create(raw_token)

    @user.update!(
      auth_token: hashed_token,
      auth_token_expires_at: TOKEN_EXPIRATION.from_now
    )

    raw_token
  end
end
