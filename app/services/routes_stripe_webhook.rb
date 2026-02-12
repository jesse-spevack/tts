class RoutesStripeWebhook
  def self.call(event:)
    new(event:).call
  end

  def initialize(event:)
    @event = event
  end

  def call
    case event.type
    when "checkout.session.completed"
      handle_checkout_completed(event.data.object)
    when "customer.subscription.updated"
      SyncsSubscription.call(stripe_subscription_id: event.data.object.id)
    when "customer.subscription.deleted"
      SyncsSubscription.call(stripe_subscription_id: event.data.object.id)
    when "invoice.payment_failed"
      subscription_id = event.data.object.subscription
      SyncsSubscription.call(stripe_subscription_id: subscription_id) if subscription_id.present?
    else
      Result.success
    end
  end

  private

  attr_reader :event

  def handle_checkout_completed(session)
    if session.subscription
      result = CreatesSubscriptionFromCheckout.call(session: session)
      if result.success?
        subscription = result.data
        SendsWelcomeEmail.call(user: subscription.user, subscription: subscription)
      end
      result
    else
      GrantsCreditFromCheckout.call(session: session)
    end
  end
end
