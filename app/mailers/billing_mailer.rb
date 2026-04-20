class BillingMailer < ApplicationMailer
  def upgrade_nudge(user)
    @user = user
    @billing_url = billing_url

    mail(
      to: user.email_address,
      subject: "We love your enthusiasm! 🎧"
    )
  end

  # `subscription:` kwarg retained for back-compat with RoutesStripeWebhook,
  # which still fires this mailer during Jesse's subscription winddown; the
  # rewritten template no longer branches on @subscription.
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

  def credit_depleted(user)
    @user = user
    @billing_url = billing_url

    mail(
      to: user.email_address,
      subject: "Your credits are used up"
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

  def subscription_ended(user)
    @user = user
    @settings_url = settings_url

    mail(
      to: user.email_address,
      subject: "Thanks for giving PodRead a spin"
    )
  end

  # One-off heads-up email for users who bought credits under the old
  # $1/credit pricing (agent-team-rbpr). Paired with the
  # pricing:legacy_migration rake task that bumps their balances.
  # This method + its template should be removed after the migration runs
  # (see follow-up bead on agent-team-wunn).
  def legacy_pricing_migration_2026_04(user:, previous_balance:, new_balance:)
    @user = user
    @previous_balance = previous_balance
    @new_balance = new_balance

    mail(
      to: user.email_address,
      subject: "Your PodRead credits just got bigger"
    )
  end
end
