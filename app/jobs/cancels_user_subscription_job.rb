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
    # Subscription doesn't exist on Stripe's side (already canceled or never
    # existed). Treat as a successful end state — do not retry. Reconcile the
    # local row so User#premium? stops returning true on a restored account.
    if e.code == "resource_missing" || e.http_status == 404
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
end
