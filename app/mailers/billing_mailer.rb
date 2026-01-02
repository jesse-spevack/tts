class BillingMailer < ApplicationMailer
  def upgrade_nudge(user)
    @user = user
    @billing_url = billing_url

    mail(
      to: user.email_address,
      subject: "Ready for more?"
    )
  end
end
