require "test_helper"

class SyncsSubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
    Stripe.api_key = "sk_test_fake"
  end

  test "creates new subscription for active Stripe subscription" do
    stub_stripe_subscription(
      id: "sub_new",
      customer: "cus_new",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    stub_stripe_customer(id: "cus_new", user_id: @user.id)

    result = SyncsSubscription.call(stripe_subscription_id: "sub_new")

    assert result.success?
    subscription = result.data
    assert_equal @user, subscription.user
    assert subscription.active?
    assert_equal "cus_new", @user.reload.stripe_customer_id
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
    stub_stripe_subscription(
      id: "sub_canceled",
      customer: "cus_canceled",
      status: "canceled",
      price_id: "price_monthly",
      current_period_end: 1.day.ago.to_i
    )

    stub_stripe_customer(id: "cus_canceled", user_id: @user.id)

    result = SyncsSubscription.call(stripe_subscription_id: "sub_canceled")

    assert result.success?
    assert result.data.canceled?
  end

  test "maps trialing status to active" do
    stub_stripe_subscription(
      id: "sub_trial",
      customer: "cus_trial",
      status: "trialing",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    stub_stripe_customer(id: "cus_trial", user_id: @user.id)

    result = SyncsSubscription.call(stripe_subscription_id: "sub_trial")

    assert result.success?
    assert result.data.active?
  end

  private

  def stub_stripe_subscription(id:, customer:, status:, price_id:, current_period_end:)
    stub_request(:get, "https://api.stripe.com/v1/subscriptions/#{id}")
      .to_return(
        status: 200,
        body: {
          id: id,
          customer: customer,
          status: status,
          items: {
            data: [ { price: { id: price_id }, current_period_end: current_period_end } ]
          }
        }.to_json
      )
  end

  def stub_stripe_customer(id:, user_id:)
    stub_request(:get, "https://api.stripe.com/v1/customers/#{id}")
      .to_return(
        status: 200,
        body: {
          id: id,
          metadata: { user_id: user_id.to_s }
        }.to_json
      )
  end
end
