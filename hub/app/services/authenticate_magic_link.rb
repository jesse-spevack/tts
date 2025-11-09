class AuthenticateMagicLink
  Result = Struct.new(:success?, :user, keyword_init: true)

  def self.call(token:)
    new(token: token).call
  end

  def initialize(token:)
    @token = token
  end

  def call
    return Result.new(success?: false, user: nil) if @token.blank?

    # Find all users with valid tokens to prevent timing attacks
    users = User.with_valid_auth_token

    user = users.find do |u|
      VerifyHashedToken.call(hashed_token: u.auth_token, raw_token: @token)
    end

    if user
      InvalidateAuthToken.call(user: user)
      Result.new(success?: true, user: user)
    else
      Result.new(success?: false, user: nil)
    end
  end
end
