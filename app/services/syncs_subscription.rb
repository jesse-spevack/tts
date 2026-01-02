class SyncsSubscription
  def self.call(stripe_subscription_id:)
    new(stripe_subscription_id:).call
  end

  def initialize(stripe_subscription_id:)
    @stripe_subscription_id = stripe_subscription_id
  end

  def call
    stripe_subscription = Stripe::Subscription.retrieve(stripe_subscription_id)
    user = User.find_by!(stripe_customer_id: stripe_subscription.customer)

    ActiveRecord::Base.transaction do
      subscription = Subscription.find_or_initialize_by(
        stripe_subscription_id: stripe_subscription.id
      )

      # Assumes single-item subscriptions (one price per subscription)
      item = stripe_subscription.items.data.first
      subscription.update!(
        user: user,
        status: map_status(stripe_subscription.status),
        stripe_price_id: item.price.id,
        current_period_end: Time.at(item.current_period_end),
        cancel_at_period_end: stripe_subscription.cancel_at_period_end
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

  def map_status(stripe_status)
    case stripe_status
    when "active", "trialing"
      :active
    when "past_due"
      :past_due
    when "canceled"
      :canceled
    else
      # Log unexpected statuses (unpaid, incomplete, incomplete_expired, paused)
      Rails.logger.warn("[SyncsSubscription] Unexpected subscription status '#{stripe_status}' mapped to :canceled")
      :canceled
    end
  end
end
