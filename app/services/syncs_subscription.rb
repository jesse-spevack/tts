# frozen_string_literal: true

class SyncsSubscription
  include StructuredLogging

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

      was_not_canceling = subscription.cancel_at.nil?
      was_persisted_and_not_canceled = subscription.persisted? && !subscription.canceled?

      # Assumes single-item subscriptions (one price per subscription)
      item = stripe_subscription.items.data.first
      new_cancel_at = derive_cancel_at(stripe_subscription, item)
      new_status = map_status(stripe_subscription.status)

      subscription.update!(
        user: user,
        status: new_status,
        stripe_price_id: item.price.id,
        current_period_end: Time.at(item.current_period_end),
        cancel_at: new_cancel_at
      )

      # Send cancellation email when subscription transitions to pending cancellation
      # (skip if subscription is also ending in this same sync — the ended email covers it)
      if was_not_canceling && new_cancel_at.present? && !subscription.canceled?
        SendsCancellationEmail.call(user: user, subscription: subscription, ends_at: new_cancel_at)
      end

      # Send subscription ended email when subscription transitions to canceled
      if was_persisted_and_not_canceled && subscription.canceled?
        SendsSubscriptionEndedEmail.call(user: user, subscription: subscription)
      end

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
      log_warn "unexpected_subscription_status", status: stripe_status, mapped_to: "canceled"
      :canceled
    end
  end

  def derive_cancel_at(stripe_subscription, item)
    if stripe_subscription.cancel_at
      Time.at(stripe_subscription.cancel_at)
    elsif stripe_subscription.cancel_at_period_end
      Time.at(item.current_period_end)
    end
  end
end
