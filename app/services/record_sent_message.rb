class RecordSentMessage
  def self.call(user:, message_type:)
    new(user:, message_type:).call
  end

  def initialize(user:, message_type:)
    @user = user
    @message_type = message_type
  end

  def call
    SentMessage.create!(user:, message_type:)
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false
  end

  private

  attr_reader :user, :message_type
end
