class BillingMailerPreview < ActionMailer::Preview
  def upgrade_nudge
    BillingMailer.upgrade_nudge(User.first)
  end

  def welcome
    user = User.joins(:subscription).first || User.first
    subscription = user.subscription || Subscription.new(stripe_subscription_id: "sub_preview")
    BillingMailer.welcome(user, subscription: subscription)
  end

  def cancellation
    BillingMailer.cancellation(User.first, ends_at: 1.month.from_now)
  end
end
