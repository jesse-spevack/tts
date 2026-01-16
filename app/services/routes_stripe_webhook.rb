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
      result = CreatesSubscriptionFromCheckout.call(session: event.data.object)
      if result.success?
        subscription = result.data
        SendsWelcomeEmail.call(user: subscription.user, subscription: subscription)
      end
      result
    when "customer.subscription.updated"
      stripe_subscription = event.data.object
      previous_attributes = event.data.previous_attributes

      # Detect cancellation: cancel_at_period_end changed from false to true
      if stripe_subscription.cancel_at_period_end &&
         previous_attributes&.dig("cancel_at_period_end") == false
        user = User.find_by(stripe_customer_id: stripe_subscription.customer)
        subscription = Subscription.find_by(stripe_subscription_id: stripe_subscription.id)
        if user && subscription
          ends_at = Time.at(stripe_subscription.current_period_end)
          SendsCancellationEmail.call(user: user, subscription: subscription, ends_at: ends_at)
        end
      end

      SyncsSubscription.call(stripe_subscription_id: stripe_subscription.id)
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
end
