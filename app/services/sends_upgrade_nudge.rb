class SendsUpgradeNudge
  def self.call(user:)
    new(user:).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return Result.failure("Not a free user") unless user.free?
    return Result.failure("Already sent this month") if already_sent_this_month?

    BillingMailer.upgrade_nudge(user).deliver_later
    user.sent_messages.create!(message_type: message_type_for_month)

    Result.success
  end

  private

  attr_reader :user

  def already_sent_this_month?
    user.sent_messages.exists?(message_type: message_type_for_month)
  end

  def message_type_for_month
    "upgrade_nudge_#{Date.current.strftime('%Y_%m')}"
  end
end
