class SendMagicLink
  Result = Struct.new(:success?, :user, keyword_init: true)

  def self.call(email_address:)
    new(email_address: email_address).call
  end

  def initialize(email_address:)
    @email_address = email_address
  end

  def call
    user = User.find_or_create_by(email_address: @email_address)

    if user.persisted?
      user.generate_auth_token!
      SessionsMailer.magic_link(user).deliver_later
      Result.new(success?: true, user: user)
    else
      Result.new(success?: false, user: nil)
    end
  end
end
