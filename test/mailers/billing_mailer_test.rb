# frozen_string_literal: true

require "test_helper"

# iny7 decision 3: sweep ALL billing mailer templates to remove
# subscription upsell language. The hardest case is credit_depleted, which
# currently pitches "$9/month" — an offer that no longer exists.
#
# Post-winddown (agent-team-9rt7), welcome/cancellation/subscription_ended
# mailers were removed with the rest of the subscription code.
# upgrade_nudge either gets rewritten to pitch credit packs or deleted +
# all callers removed. Pick the lightest-weight option and assert here.
class BillingMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:one)
  end

  # --- credit_depleted: worst offender, pitches $9/month today ---

  test "credit_depleted mail does not pitch a $9/month subscription" do
    mail = BillingMailer.credit_depleted(@user)

    body = mail.body.to_s
    refute_match(/\$9\/month/, body,
      "credit_depleted must stop offering $9/month — that product doesn't exist post-iny7")
    refute_match(/Premium subscription/i, body,
      "credit_depleted must stop pitching a Premium subscription")
    refute_match(/\bsubscription\b/i, body,
      "credit_depleted must not mention subscription at all")
    refute_match(/Unlimited episodes/i, body,
      "credit_depleted must stop promising unlimited episodes")
  end

  test "credit_depleted mail points users to buy more credits at /billing" do
    mail = BillingMailer.credit_depleted(@user)
    body = mail.body.to_s

    assert_match(/Buy more credits/i, body,
      "credit_depleted must offer the credit-pack path forward")
    assert_match(%r{/billing}, body,
      "credit_depleted must link to /billing")
  end

  # --- upgrade_nudge: rewritten for credits OR deleted with callers ---

  test "upgrade_nudge does not pitch $9/month or $89/year subscription" do
    # Pick up either outcome: if the method still exists it must pitch
    # credits; if callers + action are both deleted this test is moot —
    # the sweep test in test/views/iny7_sweep_test.rb covers the 'deleted'
    # case by ensuring no view still calls it.
    skip "upgrade_nudge was removed" unless BillingMailer.instance_methods.include?(:upgrade_nudge)

    user = users(:free_user)
    mail = BillingMailer.upgrade_nudge(user)
    body = mail.body.to_s

    refute_match(/\$9\/month/, body,
      "upgrade_nudge must not sell subscriptions post-iny7")
    refute_match(/\$89\/year/, body,
      "upgrade_nudge must not sell annual subscriptions post-iny7")
    refute_match(/Upgrade to Premium/i, body,
      "upgrade_nudge must not pitch Premium upgrade copy")
  end
end
