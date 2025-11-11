class CreateUser
  Result = Struct.new(:success?, :user, :podcast, keyword_init: true)

  def self.call(email_address:)
    new(email_address: email_address).call
  end

  def initialize(email_address:)
    @email_address = email_address
  end

  def call
    user = nil
    podcast = nil

    ActiveRecord::Base.transaction do
      user = User.create!(email_address: @email_address)
      podcast = CreateDefaultPodcast.call(user: user)
    end

    Result.new(success?: true, user: user, podcast: podcast)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, user: nil, podcast: nil)
  end
end
