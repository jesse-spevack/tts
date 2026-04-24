require "test_helper"
require "ostruct"

class RoutesStripeWebhookTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = users(:free_user)
    Stripe.api_key = "sk_test_fake"
  end

  test "routes checkout.session.completed (credit pack) to GrantsCreditFromCheckout" do
    user = users(:one)
    user.update!(stripe_customer_id: "cus_credit_pack")
    pack_5_price_id = AppConfig::Credits::PACKS.find { |p| p[:size] == 5 }[:stripe_price_id]

    event = OpenStruct.new(
      type: "checkout.session.completed",
      data: OpenStruct.new(object: OpenStruct.new(
        id: "cs_credit_pack_test",
        customer: "cus_credit_pack",
        metadata: OpenStruct.new(price_id: pack_5_price_id)
      ))
    )

    result = RoutesStripeWebhook.call(event: event)

    assert result.success?
    assert_equal 5, user.credits_remaining
  end

  test "checkout.session.completed for credit pack does not send any email" do
    user = users(:one)
    user.update!(stripe_customer_id: "cus_credit_no_email")
    pack_5_price_id = AppConfig::Credits::PACKS.find { |p| p[:size] == 5 }[:stripe_price_id]

    event = OpenStruct.new(
      type: "checkout.session.completed",
      data: OpenStruct.new(object: OpenStruct.new(
        id: "cs_credit_no_email",
        customer: "cus_credit_no_email",
        metadata: OpenStruct.new(price_id: pack_5_price_id)
      ))
    )

    assert_no_enqueued_emails do
      RoutesStripeWebhook.call(event: event)
    end
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
