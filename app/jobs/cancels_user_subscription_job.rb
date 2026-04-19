# frozen_string_literal: true

# Cancels the user's active Stripe subscription after a soft-delete so we
# don't keep charging a deleted account.
#
# Enqueued from User#soft_delete!. The user is already soft-deleted by the
# time this runs, so we look them up via `User.unscoped`. Retries transient
# Stripe API errors automatically; on retry exhaustion logs an error so
# finance can reconcile manually.
class CancelsUserSubscriptionJob < ApplicationJob
  include StructuredLogging

  # Raised when Stripe returns 404 for our stored stripe_subscription_id but
  # the customer still has an active subscription under a different id. The
  # local row has diverged from Stripe's state — we cannot safely reconcile
  # because marking it canceled would hide a sub that's still billing.
  class SubscriptionIdMismatchError < StandardError; end

  queue_as :default

  # Block-form retry_on so exhausted retries surface as log_error (Sentry per
  # project convention). Without this the job DLQ's silently and Stripe keeps
  # billing through the outage.
  retry_on Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.send(:log_error, "cancel_user_subscription_unrecoverable",
      user_id: job.arguments.first[:user_id],
      error_class: error.class.name,
      error: error.message)
  end

  retry_on Stripe::APIError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.send(:log_error, "cancel_user_subscription_unrecoverable",
      user_id: job.arguments.first[:user_id],
      error_class: error.class.name,
      error: error.message)
  end

  def perform(user_id:)
    user = User.unscoped.find_by(id: user_id)
    if user.nil?
      log_warn "cancel_user_subscription_user_missing", user_id: user_id
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
