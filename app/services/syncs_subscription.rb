class SyncsSubscription
  def self.call(stripe_subscription_id:)
    new(stripe_subscription_id:).call
  end

  def initialize(stripe_subscription_id:)
    @stripe_subscription_id = stripe_subscription_id
  end

  def call
    stripe_subscription = Stripe::Subscription.retrieve(stripe_subscription_id)

    subscription = Subscription.find_or_initialize_by(
      stripe_subscription_id: stripe_subscription.id
    )

    subscription.update!(
      user: find_user(subscription, stripe_subscription.customer),
      stripe_customer_id: stripe_subscription.customer,
      status: map_status(stripe_subscription.status),
      stripe_price_id: stripe_subscription.items.data.first.price.id,
      current_period_end: Time.at(stripe_subscription.current_period_end)
    )

    Result.success(subscription)
  rescue Stripe::StripeError => e
    Result.failure("Stripe API error: #{e.message}")
  end

  private

  attr_reader :stripe_subscription_id

  def find_user(subscription, stripe_customer_id)
    return subscription.user if subscription.persisted?

    customer = Stripe::Customer.retrieve(stripe_customer_id)
    User.find(customer.metadata["user_id"])
  end

  def map_status(stripe_status)
    case stripe_status
    when "active", "trialing"
      :active
    when "past_due"
      :past_due
    else
      :canceled
    end
  end
end
