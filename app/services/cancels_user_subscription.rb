# frozen_string_literal: true

# Cancels a user's active Stripe subscription and reconciles the local row.
# Used after account deactivation so a deactivated account stops being
# charged. Stripe::APIConnectionError / Stripe::APIError propagate up to
# CancelsUserSubscriptionJob for retry; SubscriptionIdMismatchError is
# raised when a 404 masks a real billing mismatch.
class CancelsUserSubscription
  include StructuredLogging

  # Raised when Stripe returns 404 for our stored stripe_subscription_id but
  # the customer still has an active subscription under a different id.
  # Marking the local row canceled in that case would hide a sub that's still
  # billing — we raise so finance reconciles manually.
  class SubscriptionIdMismatchError < StandardError; end

  def self.call(user_id:)
    new(user_id: user_id).call
  end

  def initialize(user_id:)
    @user_id = user_id
  end

  def call
    user = User.find_by(id: @user_id)
    if user.nil?
      log_warn "cancel_user_subscription_user_missing", user_id: @user_id
      return
    end

    subscription = user.subscription
    if subscription.nil?
      log_info "cancel_user_subscription_no_subscription", user_id: user.id
      return
    end

    Stripe::Subscription.cancel(subscription.stripe_subscription_id)
    reconcile_local_subscription(subscription)
    log_info "cancel_user_subscription_success",
      user_id: user.id,
      stripe_subscription_id: subscription.stripe_subscription_id
  rescue Stripe::InvalidRequestError => e
    # 404 could mean "already canceled" (safe) OR "our stored id was wrong
    # and the real sub is still billing" (dangerous). Verify with Stripe
    # before reconciling the local row.
    if e.code == "resource_missing" || e.http_status == 404
      if customer_has_active_subscription?(user)
        log_error "cancel_user_subscription_id_mismatch",
          user_id: user&.id,
          stripe_customer_id: user&.stripe_customer_id,
          stored_stripe_subscription_id: subscription&.stripe_subscription_id,
          reason: "stripe_404_but_customer_has_active_subscription"
        raise SubscriptionIdMismatchError,
          "Stripe 404 for #{subscription&.stripe_subscription_id} but customer #{user&.stripe_customer_id} has an active subscription"
      end

      reconcile_local_subscription(subscription)
      log_warn "cancel_user_subscription_already_gone",
        user_id: user&.id,
        stripe_subscription_id: subscription&.stripe_subscription_id,
        reason: e.message
    else
      log_error "cancel_user_subscription_invalid_request",
        user_id: user&.id,
        stripe_subscription_id: subscription&.stripe_subscription_id,
        error: e.message
      raise
    end
  rescue Stripe::StripeError => e
    log_error "cancel_user_subscription_stripe_error",
      user_id: user&.id,
      stripe_subscription_id: subscription&.stripe_subscription_id,
      error: e.message
    raise
  end

  private

  def reconcile_local_subscription(subscription)
    return if subscription.canceled?

    subscription.update!(status: :canceled, canceled_at: Time.current)
  end

  def customer_has_active_subscription?(user)
    return false unless user&.stripe_customer_id

    Stripe::Subscription.list(customer: user.stripe_customer_id, status: "active", limit: 1).data.any?
  end
end
