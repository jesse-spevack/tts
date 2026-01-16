class SendsWelcomeEmail
  def self.call(user:, subscription:)
    new(user:, subscription:).call
  end

  def initialize(user:, subscription:)
    @user = user
    @subscription = subscription
  end

  def call
    return Result.failure("Already sent") if already_sent?

    BillingMailer.welcome(user, subscription:).deliver_later
    user.sent_messages.create!(message_type: message_type)

    Result.success
  end

  private

  attr_reader :user, :subscription

  def already_sent?
    user.sent_messages.exists?(message_type: message_type)
  end

  def message_type
    "welcome_#{subscription.stripe_subscription_id}"
  end
end
