require "test_helper"
require "ostruct"

class RoutesStripeWebhookTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
    Stripe.api_key = "sk_test_fake"
  end

  test "routes checkout.session.completed to CreatesSubscriptionFromCheckout" do
    # Stub the Stripe API calls that will be made
    stub_request(:get, "https://api.stripe.com/v1/subscriptions/sub_test")
      .to_return(
        status: 200,
        body: {
          id: "sub_test",
          customer: "cus_test",
          status: "active",
          current_period_end: 1.month.from_now.to_i,
          items: { data: [ { price: { id: "price_monthly" } } ] }
        }.to_json
      )

    stub_request(:get, "https://api.stripe.com/v1/customers/cus_test")
      .to_return(
        status: 200,
        body: { id: "cus_test", metadata: { user_id: @user.id.to_s } }.to_json
      )

    event = OpenStruct.new(
      type: "checkout.session.completed",
      data: OpenStruct.new(object: OpenStruct.new(id: "cs_test", subscription: "sub_test"))
    )

    result = RoutesStripeWebhook.call(event: event)

    assert result.success?
    assert Subscription.exists?(stripe_subscription_id: "sub_test")
  end

  test "routes customer.subscription.updated to SyncsSubscription" do
    # Create existing subscription
    @user.update!(stripe_customer_id: "cus_test")
    subscription = Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_test",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.week.from_now
    )

    stub_request(:get, "https://api.stripe.com/v1/subscriptions/sub_test")
      .to_return(
        status: 200,
        body: {
          id: "sub_test",
          customer: "cus_test",
          status: "past_due",
          current_period_end: 1.month.from_now.to_i,
          items: { data: [ { price: { id: "price_monthly" } } ] }
        }.to_json
      )

    event = OpenStruct.new(
      type: "customer.subscription.updated",
      data: OpenStruct.new(object: OpenStruct.new(id: "sub_test"))
    )

    result = RoutesStripeWebhook.call(event: event)

    assert result.success?
    subscription.reload
    assert subscription.past_due?
  end

  test "routes customer.subscription.deleted to SyncsSubscription" do
    # Create existing subscription
    @user.update!(stripe_customer_id: "cus_del")
    subscription = Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_deleted",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.week.from_now
    )

    stub_request(:get, "https://api.stripe.com/v1/subscriptions/sub_deleted")
      .to_return(
        status: 200,
        body: {
          id: "sub_deleted",
          customer: "cus_del",
          status: "canceled",
          current_period_end: 1.day.ago.to_i,
          items: { data: [ { price: { id: "price_monthly" } } ] }
        }.to_json
      )

    event = OpenStruct.new(
      type: "customer.subscription.deleted",
      data: OpenStruct.new(object: OpenStruct.new(id: "sub_deleted"))
    )

    result = RoutesStripeWebhook.call(event: event)

    assert result.success?
    subscription.reload
    assert subscription.canceled?
  end

  test "routes invoice.payment_failed to SyncsSubscription" do
    # Create existing subscription
    @user.update!(stripe_customer_id: "cus_fail")
    subscription = Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_failed",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.week.from_now
    )

    stub_request(:get, "https://api.stripe.com/v1/subscriptions/sub_failed")
      .to_return(
        status: 200,
        body: {
          id: "sub_failed",
          customer: "cus_fail",
          status: "past_due",
          current_period_end: 1.month.from_now.to_i,
          items: { data: [ { price: { id: "price_monthly" } } ] }
        }.to_json
      )

    event = OpenStruct.new(
      type: "invoice.payment_failed",
      data: OpenStruct.new(object: OpenStruct.new(subscription: "sub_failed"))
    )

    result = RoutesStripeWebhook.call(event: event)

    assert result.success?
    subscription.reload
    assert subscription.past_due?
  end

  test "invoice.payment_failed with nil subscription is ignored" do
    event = OpenStruct.new(
      type: "invoice.payment_failed",
      data: OpenStruct.new(object: OpenStruct.new(subscription: nil))
    )

    result = RoutesStripeWebhook.call(event: event)
    assert_nil result
  end

  test "ignores unhandled event types" do
    event = OpenStruct.new(
      type: "customer.created",
      data: OpenStruct.new(object: OpenStruct.new(id: "cus_test"))
    )

    result = RoutesStripeWebhook.call(event: event)
    assert result.success?
  end
end
