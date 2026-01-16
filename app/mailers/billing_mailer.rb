class BillingMailer < ApplicationMailer
  def upgrade_nudge(user)
    @user = user
    @billing_url = billing_url

    mail(
      to: user.email_address,
      subject: "We love your enthusiasm! 🎧"
    )
  end

  def welcome(user, subscription:)
    @user = user
    @subscription = subscription
    @new_episode_url = new_episode_url
    @settings_url = settings_url

    mail(
      to: user.email_address,
      subject: "You're in! (We're a little excited)"
    )
  end

  def cancellation(user, ends_at:)
    @user = user
    @ends_at = ends_at
    @settings_url = settings_url

    mail(
      to: user.email_address,
      subject: "You're all set"
    )
  end
end
