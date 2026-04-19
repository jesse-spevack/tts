# frozen_string_literal: true

require "test_helper"

class CancelsUserSubscriptionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Stripe.api_key = "sk_test_fake"
  end

  test "cancels active Stripe subscription for soft-deleted user" do
    user = users(:free_user)
    Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_cancel_me",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(deleted_at: Time.current)

    stub = stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_cancel_me")
      .to_return(
        status: 200,
        body: { id: "sub_cancel_me", status: "canceled" }.to_json
      )

    CancelsUserSubscriptionJob.perform_now(user_id: user.id)

    assert_requested stub
  end

  test "returns early with a log when user has no subscription" do
    # users(:one) has no subscription fixture attached.
    user = users(:one)
    user.update!(deleted_at: Time.current)

    # No subscription row; no Stripe request should be made.
    assert_nothing_raised do
      CancelsUserSubscriptionJob.perform_now(user_id: user.id)
    end
  end

  test "looks up user via unscoped (user is soft-deleted when job runs)" do
    user = users(:free_user)
    Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_unscoped_lookup",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(deleted_at: Time.current)

    stub = stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_unscoped_lookup")
      .to_return(status: 200, body: { id: "sub_unscoped_lookup", status: "canceled" }.to_json)

    CancelsUserSubscriptionJob.perform_now(user_id: user.id)
    assert_requested stub
  end

  test "treats Stripe 404 (subscription missing) as success when customer has no active subs" do
    user = users(:free_user)
    user.update!(stripe_customer_id: "cus_no_active")
    Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_already_gone",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(deleted_at: Time.current)

    stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_already_gone")
      .to_return(
        status: 404,
        body: { error: { message: "No such subscription", code: "resource_missing" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Before reconciling, the job verifies with Stripe that the customer
    # truly has no active subscriptions — guards against wrong-ID mismatch.
    stub_request(:get, %r{\Ahttps://api\.stripe\.com/v1/subscriptions})
      .with(query: hash_including(customer: "cus_no_active", status: "active"))
      .to_return(
        status: 200,
        body: { data: [], has_more: false }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Should not raise or re-enqueue. Subscription already gone from Stripe's
    # side AND customer has no other active subs = desirable end state.
    assert_nothing_raised do
      CancelsUserSubscriptionJob.perform_now(user_id: user.id)
    end
  end

  test "raises and logs error when Stripe 404 masks a wrong-ID mismatch" do
    # Threat: our stripe_subscription_id was wrong from day one (env mismatch,
    # truncated value, lost webhook). Treating 404 as success marks the local
    # row canceled while the real subscription keeps billing.
    user = users(:free_user)
    user.update!(stripe_customer_id: "cus_wrong_id")
    subscription = Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_wrong_id",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(deleted_at: Time.current)

    stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_wrong_id")
      .to_return(
        status: 404,
        body: { error: { message: "No such subscription", code: "resource_missing" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Customer has a REAL active sub that we weren't tracking (different id).
    stub_request(:get, %r{\Ahttps://api\.stripe\.com/v1/subscriptions})
      .with(query: hash_including(customer: "cus_wrong_id", status: "active"))
      .to_return(
        status: 200,
        body: { data: [ { id: "sub_actually_billing", status: "active" } ], has_more: false }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    log_output = capture_logs do
      assert_raises(CancelsUserSubscriptionJob::SubscriptionIdMismatchError) do
        CancelsUserSubscriptionJob.perform_now(user_id: user.id)
      end
    end

    assert_match(/event=cancel_user_subscription_id_mismatch/, log_output)
    assert_match(/user_id=#{user.id}/, log_output)
    # Local row MUST NOT be marked canceled — real sub is still billing.
    assert_not subscription.reload.canceled?
  end

  test "soft_delete! enqueues the job" do
    user = users(:one)

    assert_enqueued_with(job: CancelsUserSubscriptionJob, args: [ { user_id: user.id } ]) do
      user.soft_delete!
    end
  end

  # Reconciliation: a successful Stripe cancel must also flip the local
  # Subscription row to canceled. Otherwise User#premium? keeps returning true
  # until current_period_end and a restored user gets free premium access.
  test "marks the local subscription canceled after successful Stripe cancel" do
    user = users(:free_user)
    subscription = Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_reconcile_local",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(deleted_at: Time.current)

    stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_reconcile_local")
      .to_return(status: 200, body: { id: "sub_reconcile_local", status: "canceled" }.to_json)

    freeze_time do
      CancelsUserSubscriptionJob.perform_now(user_id: user.id)

      subscription.reload
      assert subscription.canceled?
      assert_equal Time.current, subscription.canceled_at
    end
  end

  test "marks the local subscription canceled when Stripe returns 404" do
    user = users(:free_user)
    user.update!(stripe_customer_id: "cus_reconcile_404")
    subscription = Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_already_gone_reconcile",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(deleted_at: Time.current)

    stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_already_gone_reconcile")
      .to_return(
        status: 404,
        body: { error: { message: "No such subscription", code: "resource_missing" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, %r{\Ahttps://api\.stripe\.com/v1/subscriptions})
      .with(query: hash_including(customer: "cus_reconcile_404", status: "active"))
      .to_return(
        status: 200,
        body: { data: [], has_more: false }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    CancelsUserSubscriptionJob.perform_now(user_id: user.id)

    assert subscription.reload.canceled?
    assert_not_nil subscription.canceled_at
  end

  test "restored user with reconciled subscription is not premium" do
    user = users(:free_user)
    Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_restore_premium_check",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(deleted_at: Time.current)

    stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_restore_premium_check")
      .to_return(status: 200, body: { id: "sub_restore_premium_check", status: "canceled" }.to_json)

    CancelsUserSubscriptionJob.perform_now(user_id: user.id)
    user.restore!

    refute user.reload.premium?
  end

  test "logs error when Stripe::APIConnectionError retries are exhausted" do
    user = users(:free_user)
    Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_connection_exhausted",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(deleted_at: Time.current)

    stub = stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_connection_exhausted")
      .to_raise(Stripe::APIConnectionError.new("connection refused"))

    log_output = capture_logs do
      perform_enqueued_jobs do
        CancelsUserSubscriptionJob.perform_later(user_id: user.id)
      end
    end

    # Belt + suspenders: assert the unrecoverable log AND that all 5 attempts
    # were actually made, not just the first. Without the times: assertion the
    # test would also pass if retry_on were misconfigured and the block fired
    # on the first failure.
    assert_requested stub, times: 5
    assert_match(/event=cancel_user_subscription_unrecoverable/, log_output)
    assert_match(/user_id=#{user.id}/, log_output)
    assert_match(/connection refused/, log_output)
  end

  test "logs error when Stripe::APIError retries are exhausted" do
    user = users(:free_user)
    Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_api_exhausted",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(deleted_at: Time.current)

    # Use .to_raise so the Stripe SDK's internal network-retry layer (which
    # would otherwise retry an HTTP 500 a few times before raising) is bypassed
    # and we count only ActiveJob's retry attempts.
    stub = stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_api_exhausted")
      .to_raise(Stripe::APIError.new("internal error"))

    log_output = capture_logs do
      perform_enqueued_jobs do
        CancelsUserSubscriptionJob.perform_later(user_id: user.id)
      end
    end

    assert_requested stub, times: 3
    assert_match(/event=cancel_user_subscription_unrecoverable/, log_output)
    assert_match(/user_id=#{user.id}/, log_output)
  end

  private

  def capture_logs
    original_logger = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original_logger
  end
end
