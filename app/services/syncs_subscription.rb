class SyncsSubscription
  def self.call(stripe_subscription_id:)
    new(stripe_subscription_id:).call
  end

  def initialize(stripe_subscription_id:)
    @stripe_subscription_id = stripe_subscription_id
  end

  def call
    stripe_subscription = Stripe::Subscription.retrieve(stripe_subscription_id)
    user = find_user(stripe_subscription.customer)

    ActiveRecord::Base.transaction do
      ensure_user_has_customer_id(user, stripe_subscription.customer)

      subscription = Subscription.find_or_initialize_by(
        stripe_subscription_id: stripe_subscription.id
      )

      item = stripe_subscription.items.data.first
      subscription.update!(
        user: user,
        status: map_status(stripe_subscription.status),
        stripe_price_id: item.price.id,
        current_period_end: Time.at(item.current_period_end)
      )

      Result.success(subscription)
    end
  rescue Stripe::StripeError => e
    Result.failure("Stripe API error: #{e.message}")
  rescue ActiveRecord::RecordInvalid => e
    Result.failure("Database error: #{e.message}")
  end

  private

  attr_reader :stripe_subscription_id

  def find_user(stripe_customer_id)
    User.find_by(stripe_customer_id: stripe_customer_id) || find_user_from_stripe(stripe_customer_id)
  end

  def find_user_from_stripe(stripe_customer_id)
    customer = Stripe::Customer.retrieve(stripe_customer_id)
    User.find(customer.metadata["user_id"])
  end

  def ensure_user_has_customer_id(user, stripe_customer_id)
    return if user.stripe_customer_id.present?

    user.update!(stripe_customer_id: stripe_customer_id)
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
