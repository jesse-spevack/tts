class ValidatesAuthToken
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    @user.auth_token.present? &&
      @user.auth_token_expires_at.present? &&
      @user.auth_token_expires_at.future?
  end
end
