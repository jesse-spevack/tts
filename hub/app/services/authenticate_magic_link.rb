class AuthenticateMagicLink
  Result = Struct.new(:success?, :user, keyword_init: true)

  def self.call(token:)
    new(token: token).call
  end

  def initialize(token:)
    @token = token
  end

  def call
    user = User.find_by(auth_token: @token)

    if user&.auth_token_valid?
      user.update!(auth_token: nil, auth_token_expires_at: nil)
      Result.new(success?: true, user: user)
    else
      Result.new(success?: false, user: nil)
    end
  end
end
