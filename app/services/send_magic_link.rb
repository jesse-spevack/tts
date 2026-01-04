class SendMagicLink
  def self.call(email_address:, plan: nil)
    new(email_address: email_address, plan: plan).call
  end

  def initialize(email_address:, plan: nil)
    @email_address = email_address
    @plan = plan
  end

  def call
    user = User.find_by(email_address: @email_address)

    if user.nil?
      result = CreatesUser.call(email_address: @email_address)
      return Result.failure("Could not create user") unless result.success?
      user = result.data[:user]
    end

    token = GeneratesAuthToken.call(user: user)
    SessionsMailer.magic_link(user: user, token: token, plan: @plan).deliver_later
    Result.success(user)
  end
end
