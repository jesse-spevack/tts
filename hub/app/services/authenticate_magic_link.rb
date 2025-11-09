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
    # Note: We still have timing leak in find_by, but this is acceptable for MVP
    # For production, consider hashing tokens before storage
    users = User.where.not(auth_token: nil)
                .where("auth_token_expires_at > ?", Time.current)

    # Use constant-time comparison to prevent timing attacks
    user = users.find do |u|
      ActiveSupport::SecurityUtils.secure_compare(
        u.auth_token.to_s,
        @token.to_s
      )
    end

    if user
      user.update!(auth_token: nil, auth_token_expires_at: nil)
      Result.new(success?: true, user: user)
    else
      Result.new(success?: false, user: nil)
    end
  end
end
