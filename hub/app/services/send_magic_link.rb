class SendMagicLink
  Result = Struct.new(:success?, :user, keyword_init: true)

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
      return Result.new(success?: false, user: nil) unless result.success?
      user = result.user
    end

    token = GenerateAuthToken.call(user: user)
    SessionsMailer.magic_link(user: user, token: token).deliver_later
    Result.new(success?: true, user: user)
  end
end
