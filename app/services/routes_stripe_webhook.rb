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
      CreatesSubscriptionFromCheckout.call(session: event.data.object)
    when "customer.subscription.updated", "customer.subscription.deleted"
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
end
