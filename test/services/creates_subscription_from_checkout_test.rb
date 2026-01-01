require "test_helper"
require "ostruct"

class CreatesSubscriptionFromCheckoutTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
    Stripe.api_key = "sk_test_fake"
  end

  test "syncs subscription from checkout session" do
    # Stub Stripe API calls that SyncsSubscription will make
    stub_request(:get, "https://api.stripe.com/v1/subscriptions/sub_from_checkout")
      .to_return(
        status: 200,
        body: {
          id: "sub_from_checkout",
          customer: "cus_checkout",
          status: "active",
          current_period_end: 1.month.from_now.to_i,
          items: { data: [{ price: { id: "price_monthly" } }] }
        }.to_json
      )

    stub_request(:get, "https://api.stripe.com/v1/customers/cus_checkout")
      .to_return(
        status: 200,
        body: { id: "cus_checkout", metadata: { user_id: @user.id.to_s } }.to_json
      )

    session = OpenStruct.new(subscription: "sub_from_checkout")

    result = CreatesSubscriptionFromCheckout.call(session: session)

    assert result.success?
    assert Subscription.exists?(stripe_subscription_id: "sub_from_checkout")
  end

  test "returns failure if no subscription in session" do
    session = OpenStruct.new(subscription: nil)

    result = CreatesSubscriptionFromCheckout.call(session: session)

    refute result.success?
    assert_match(/No subscription/, result.error)
  end
end
