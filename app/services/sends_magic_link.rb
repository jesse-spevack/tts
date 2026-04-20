class SendsMagicLink
  def self.call(email_address:, plan: nil, pack_size: nil)
    new(email_address: email_address, plan: plan, pack_size: pack_size).call
  end

  def initialize(email_address:, plan: nil, pack_size: nil)
    @email_address = email_address
    @plan = plan
    @pack_size = pack_size
  end

  def call
    user = User.find_by(email_address: @email_address)

    if user.nil?
      result = CreatesUser.call(email_address: @email_address)
      return Result.failure("Could not create user") unless result.success?
      user = result.data[:user]
    end

    token = GeneratesAuthToken.call(user: user)
    SessionsMailer.magic_link(user: user, token: token, plan: @plan, pack_size: @pack_size).deliver_later
    Result.success(user)
  end
end
