class SendsCancellationEmail
  def self.call(user:, subscription:, ends_at:)
    new(user:, subscription:, ends_at:).call
  end

  def initialize(user:, subscription:, ends_at:)
    @user = user
    @subscription = subscription
    @ends_at = ends_at
  end

  def call
    return Result.failure("Already sent") if already_sent?

    BillingMailer.cancellation(user, ends_at:).deliver_later
    user.sent_messages.create!(message_type: message_type)

    Result.success
  end

  private

  attr_reader :user, :subscription, :ends_at

  def already_sent?
    user.sent_messages.exists?(message_type: message_type)
  end

  def message_type
    "cancellation_#{subscription.stripe_subscription_id}"
  end
end
