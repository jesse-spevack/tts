class InvalidateAuthToken
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    @user.update!(auth_token: nil, auth_token_expires_at: nil)
    Rails.logger.info("Invalidated auth token for user #{@user.id}")
  end
end
