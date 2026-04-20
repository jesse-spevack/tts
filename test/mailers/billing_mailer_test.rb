# frozen_string_literal: true

require "test_helper"

# iny7 decision 3: sweep ALL 5 billing mailer templates to remove
# subscription upsell language. The hardest case is credit_depleted, which
# currently pitches "$9/month" — an offer that no longer exists.
#
# cancellation / subscription_ended / welcome stay functional for Jesse's
# winding-down subscription, but their copy should not introduce NEW
# subscriptions or reference a subscription plan that's no longer on sale.
#
# upgrade_nudge either gets rewritten to pitch credit packs or deleted +
# all callers removed. Pick the lightest-weight option and assert here.
class BillingMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:subscriber)
    @subscription = @user.subscription
    @ends_at = 1.month.from_now
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

  # --- welcome: no "subscription lives in Settings" language ---

  test "welcome mail does not describe a subscription" do
    mail = BillingMailer.welcome(@user, subscription: @subscription)
    body = mail.body.to_s

    refute_match(/subscription lives in Settings/i, body,
      "welcome must not anchor the UX around a subscription after iny7")
    refute_match(/Thanks for subscribing/i, body,
      "welcome must not say 'Thanks for subscribing' — users buy credits now")
  end

  # --- cancellation: stays functional but no resubscribe upsell ---

  test "cancellation mail does not pitch resubscribing" do
    mail = BillingMailer.cancellation(@user, ends_at: @ends_at)
    body = mail.body.to_s

    refute_match(/resubscribe/i, body,
      "cancellation must not point users at a resubscribe flow post-iny7")
  end

  # --- subscription_ended: functional, no new subscription pitch ---

  test "subscription_ended mail does not pitch a new subscription" do
    mail = BillingMailer.subscription_ended(@user)
    body = mail.body.to_s

    refute_match(/pick it back up/i, body,
      "subscription_ended must not tell users to resubscribe")
    refute_match(/subscribe/i, body,
      "subscription_ended must not pitch a new subscription")
  end

  # --- upgrade_nudge: rewritten for credits OR deleted with callers ---

  # --- legacy_pricing_migration_2026_04 (agent-team-rbpr) ---

  test "legacy_pricing_migration_2026_04 sends to user email with correct subject" do
    user = users(:credit_user)
    mail = BillingMailer.legacy_pricing_migration_2026_04(
      user: user,
      previous_balance: 5,
      new_balance: 30
    )

    assert_equal [ user.email_address ], mail.to
    assert_equal "Your PodRead credits just got bigger", mail.subject
  end

  test "legacy_pricing_migration_2026_04 body interpolates previous and new balance" do
    user = users(:credit_user)
    mail = BillingMailer.legacy_pricing_migration_2026_04(
      user: user,
      previous_balance: 5,
      new_balance: 30
    )
    body = mail.body.encoded

    assert_match "You went from 5 to 30", body
  end

  test "legacy_pricing_migration_2026_04 includes the approved copy" do
    user = users(:credit_user)
    mail = BillingMailer.legacy_pricing_migration_2026_04(
      user: user,
      previous_balance: 3,
      new_balance: 26
    )
    body = mail.body.encoded

    assert_match "Thanks for giving PodRead a try", body
    assert_match "Credits used to be $1 each. They're $2 now.", body
    assert_match "Long articles over 20,000 characters with a Premium voice cost 2 credits instead of 1", body
    assert_match "doubled your balance and added 20 credits on top", body
    assert_match "jesse@podread.app", body
  end

  test "legacy_pricing_migration_2026_04 sends from Jesse's personal address so replies land in his inbox" do
    user = users(:credit_user)
    mail = BillingMailer.legacy_pricing_migration_2026_04(
      user: user,
      previous_balance: 5,
      new_balance: 30
    )

    assert_equal [ "jesse@podread.app" ], mail.from
    assert_equal "Jesse <jesse@podread.app>", mail[:from].value
  end

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
