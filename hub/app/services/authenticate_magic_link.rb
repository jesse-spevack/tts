class AuthenticateMagicLink
  Result = Struct.new(:success?, :user, keyword_init: true)

  def authenticate(token)
    user = User.find_by(auth_token: token)

    if user&.auth_token_valid?
      user.update!(auth_token: nil, auth_token_expires_at: nil)
      Result.new(success?: true, user: user)
    else
      Result.new(success?: false, user: nil)
    end
  end
end
