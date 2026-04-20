# frozen_string_literal: true

require "test_helper"

class CancelsUserSubscriptionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Stripe.api_key = "sk_test_fake"
  end

  test "cancels active Stripe subscription for deactivated user" do
    user = users(:free_user)
    Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_cancel_me",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(active: false)

    stub = stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_cancel_me")
      .to_return(
        status: 200,
        body: { id: "sub_cancel_me", status: "canceled" }.to_json
      )

    CancelsUserSubscriptionJob.perform_now(user_id: user.id)

    assert_requested stub
  end

  test "returns early with a log when user has no subscription" do
    user = users(:one)
    user.update!(active: false)

    assert_nothing_raised do
      CancelsUserSubscriptionJob.perform_now(user_id: user.id)
    end
  end

  test "returns early when user not found" do
    assert_nothing_raised do
      CancelsUserSubscriptionJob.perform_now(user_id: 999_999_999)
    end
  end

  test "treats Stripe 404 as success when customer has no active subs" do
    user = users(:free_user)
    user.update!(stripe_customer_id: "cus_no_active")
    Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_already_gone",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(active: false)

    stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_already_gone")
      .to_return(
        status: 404,
        body: { error: { message: "No such subscription", code: "resource_missing" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, %r{\Ahttps://api\.stripe\.com/v1/subscriptions})
      .with(query: hash_including(customer: "cus_no_active", status: "active"))
      .to_return(
        status: 200,
        body: { data: [], has_more: false }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_nothing_raised do
      CancelsUserSubscriptionJob.perform_now(user_id: user.id)
    end
  end

  test "raises and logs error when Stripe 404 masks a wrong-ID mismatch" do
    user = users(:free_user)
    user.update!(stripe_customer_id: "cus_wrong_id")
    subscription = Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_wrong_id",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(active: false)

    stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_wrong_id")
      .to_return(
        status: 404,
        body: { error: { message: "No such subscription", code: "resource_missing" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, %r{\Ahttps://api\.stripe\.com/v1/subscriptions})
      .with(query: hash_including(customer: "cus_wrong_id", status: "active"))
      .to_return(
        status: 200,
        body: { data: [ { id: "sub_actually_billing", status: "active" } ], has_more: false }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    log_output = capture_logs do
      assert_raises(CancelsUserSubscription::SubscriptionIdMismatchError) do
        CancelsUserSubscriptionJob.perform_now(user_id: user.id)
      end
    end

    assert_match(/event=cancel_user_subscription_id_mismatch/, log_output)
    assert_match(/user_id=#{user.id}/, log_output)
    assert_not subscription.reload.canceled?
  end

  test "marks the local subscription canceled after successful Stripe cancel" do
    user = users(:free_user)
    subscription = Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_reconcile_local",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(active: false)

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
    user.update!(active: false)

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

  # B1: retry_on Stripe::StripeError covers the entire Stripe error hierarchy,
  # including auth errors (Stripe::AuthenticationError) and rate-limit errors
  # (Stripe::RateLimitError), which are subclasses of StripeError but NOT of
  # APIConnectionError or APIError. The original PR #290 retry_on set would
  # miss them.
  test "logs unrecoverable error when retries are exhausted for Stripe::StripeError" do
    user = users(:free_user)
    Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_exhausted",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(active: false)

    stub = stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_exhausted")
      .to_raise(Stripe::APIConnectionError.new("connection refused"))

    log_output = capture_logs do
      perform_enqueued_jobs do
        CancelsUserSubscriptionJob.perform_later(user_id: user.id)
      end
    end

    # retry_on Stripe::StripeError with attempts: 3 — three total attempts.
    assert_requested stub, times: 3
    assert_match(/event=cancel_user_subscription_unrecoverable/, log_output)
    assert_match(/user_id=#{user.id}/, log_output)
    assert_match(/connection refused/, log_output)
  end

  test "retry_on catches rate-limit errors (subclass of StripeError)" do
    user = users(:free_user)
    Subscription.create!(
      user: user,
      stripe_subscription_id: "sub_rate_limited",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now
    )
    user.update!(active: false)

    stub = stub_request(:delete, "https://api.stripe.com/v1/subscriptions/sub_rate_limited")
      .to_raise(Stripe::RateLimitError.new("too many requests"))

    log_output = capture_logs do
      perform_enqueued_jobs do
        CancelsUserSubscriptionJob.perform_later(user_id: user.id)
      end
    end

    assert_requested stub, times: 3
    assert_match(/event=cancel_user_subscription_unrecoverable/, log_output)
    assert_match(/user_id=#{user.id}/, log_output)
  end

  # B2: defensive against an ActiveJob adapter that surfaces arguments with
  # string keys only (no _aj_ruby2_keywords marker). Rails 8.1's serialize/
  # deserialize currently restores symbol keys via the marker, but the ||
  # fallback in the retry_on block is cheap insurance: if an adapter or
  # future Rails change drops the marker, user_id must still appear in the
  # unrecoverable log line for incident triage. We verify the fallback
  # logic independently by constructing a string-keyed argument hash.
  test "retry_on block reads user_id even when arguments use string keys" do
    user = users(:free_user)

    # Simulate a job whose arguments came back string-keyed (the failure
    # mode the || fallback defends against).
    fake_job = Struct.new(:arguments).new([ { "user_id" => user.id } ])
    resolved = fake_job.arguments.first[:user_id] || fake_job.arguments.first["user_id"]
    assert_equal user.id, resolved,
      "retry_on block must fall back to string-key lookup when the symbol-key lookup returns nil"

    # Verify the symbol-keyed path still works (the Rails 8.1 common case).
    real_job = CancelsUserSubscriptionJob.new(user_id: user.id)
    resolved_symbol = real_job.arguments.first[:user_id] || real_job.arguments.first["user_id"]
    assert_equal user.id, resolved_symbol
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
