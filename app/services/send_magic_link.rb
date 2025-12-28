class SendMagicLink
  def self.call(email_address:)
    new(email_address: email_address).call
  end

  def initialize(email_address:)
    @email_address = email_address
  end

  def call
    user = User.find_by(email_address: @email_address)

    if user.nil?
      result = CreateUser.call(email_address: @email_address)
      return Result.failure("Could not create user") unless result.success?
      user = result.data[:user]
    end

    token = GenerateAuthToken.call(user: user)
    SessionsMailer.magic_link(user: user, token: token).deliver_later
    Result.success(user)
  end
end
