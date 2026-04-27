class BillingMailer < ApplicationMailer
  def upgrade_nudge(user)
    @user = user
    @billing_url = billing_url

    mail(
      to: user.email_address,
      subject: "We love your enthusiasm! 🎧"
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
end
