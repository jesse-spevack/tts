class BillingMailerPreview < ActionMailer::Preview
  def upgrade_nudge
    BillingMailer.upgrade_nudge(User.first)
  end

  def credit_depleted
    BillingMailer.credit_depleted(User.first)
  end
end
