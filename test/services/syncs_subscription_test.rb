require "test_helper"

class SyncsSubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
    Stripe.api_key = "sk_test_fake"
  end

  test "creates new subscription for active Stripe subscription" do
    @user.update!(stripe_customer_id: "cus_new")

    stub_stripe_subscription(
      id: "sub_new",
      customer: "cus_new",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    result = SyncsSubscription.call(stripe_subscription_id: "sub_new")

    assert result.success?
    subscription = result.data
    assert_equal @user, subscription.user
    assert subscription.active?
  end

  test "updates existing subscription" do
    @user.update!(stripe_customer_id: "cus_existing")
    subscription = Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_existing",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.week.from_now
    )

    stub_stripe_subscription(
      id: "sub_existing",
      customer: "cus_existing",
      status: "past_due",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    result = SyncsSubscription.call(stripe_subscription_id: "sub_existing")

    assert result.success?
    subscription.reload
    assert subscription.past_due?
  end

  test "sets canceled status for canceled subscription" do
    @user.update!(stripe_customer_id: "cus_canceled")

    stub_stripe_subscription(
      id: "sub_canceled",
      customer: "cus_canceled",
      status: "canceled",
      price_id: "price_monthly",
      current_period_end: 1.day.ago.to_i
    )

    result = SyncsSubscription.call(stripe_subscription_id: "sub_canceled")

    assert result.success?
    assert result.data.canceled?
  end

  test "maps trialing status to active" do
    @user.update!(stripe_customer_id: "cus_trial")

    stub_stripe_subscription(
      id: "sub_trial",
      customer: "cus_trial",
      status: "trialing",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    result = SyncsSubscription.call(stripe_subscription_id: "sub_trial")

    assert result.success?
    assert result.data.active?
  end

  test "syncs cancel_at when Stripe has cancel_at timestamp" do
    @user.update!(stripe_customer_id: "cus_cancel_at")
    cancel_timestamp = 1.month.from_now.to_i

    stub_stripe_subscription(
      id: "sub_cancel_at",
      customer: "cus_cancel_at",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i,
      cancel_at: cancel_timestamp
    )

    result = SyncsSubscription.call(stripe_subscription_id: "sub_cancel_at")

    assert result.success?
    assert_in_delta Time.at(cancel_timestamp), result.data.cancel_at, 1.second
  end

  test "derives cancel_at from current_period_end when cancel_at_period_end is true" do
    @user.update!(stripe_customer_id: "cus_period_end")
    period_end = 1.month.from_now.to_i

    stub_stripe_subscription(
      id: "sub_period_end",
      customer: "cus_period_end",
      status: "active",
      price_id: "price_monthly",
      current_period_end: period_end,
      cancel_at_period_end: true
    )

    result = SyncsSubscription.call(stripe_subscription_id: "sub_period_end")

    assert result.success?
    assert_in_delta Time.at(period_end), result.data.cancel_at, 1.second
  end

  test "sets cancel_at to nil when subscription is not canceling" do
    @user.update!(stripe_customer_id: "cus_not_canceling")

    stub_stripe_subscription(
      id: "sub_not_canceling",
      customer: "cus_not_canceling",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i,
      cancel_at_period_end: false,
      cancel_at: nil
    )

    result = SyncsSubscription.call(stripe_subscription_id: "sub_not_canceling")

    assert result.success?
    assert_nil result.data.cancel_at
  end

  private

  def stub_stripe_subscription(id:, customer:, status:, price_id:, current_period_end:, cancel_at_period_end: false, cancel_at: nil)
    stub_request(:get, "https://api.stripe.com/v1/subscriptions/#{id}")
      .to_return(
        status: 200,
        body: {
          id: id,
          customer: customer,
          status: status,
          cancel_at_period_end: cancel_at_period_end,
          cancel_at: cancel_at,
          items: {
            data: [ { price: { id: price_id }, current_period_end: current_period_end } ]
          }
        }.to_json
      )
  end
end
