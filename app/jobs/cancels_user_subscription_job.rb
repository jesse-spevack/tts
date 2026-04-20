# frozen_string_literal: true

# Async wrapper around CancelsUserSubscription. Enqueued from DeactivatesUser
# so the local deactivation commits immediately and Stripe cleanup retries
# on its own. Retry + logging live here; the business logic lives in the
# service.
class CancelsUserSubscriptionJob < ApplicationJob
  include StructuredLogging

  queue_as :default

  # Block-form retry_on so exhausted retries surface as log_error (Sentry per
  # project convention). Without this the job DLQs silently and Stripe keeps
  # billing through the outage.
  #
  # B1: cover the retry-worthy Stripe error classes — not just APIConnection
  # and APIError (PR #290's original set), but also auth failures and
  # rate-limit errors, which are common during key rotation or burst traffic
  # and would otherwise DLQ without the unrecoverable log.
  #
  # We deliberately DO NOT catch Stripe::StripeError wholesale here because
  # ActiveSupport::Rescuable walks the exception.cause chain. The service
  # wraps 404-with-wrong-id as SubscriptionIdMismatchError whose cause is
  # Stripe::InvalidRequestError — catching StripeError would pull that
  # billing-reconciliation signal into the retry path and silently swallow
  # it after retries.
  #
  # B2: ActiveJob serializes keyword args and deserializes them with string
  # keys on some adapters. `job.arguments.first[:user_id]` returns nil once
  # the job has round-tripped; fall back to the string key so the log line
  # carries the real user_id for incident triage.
  RETRIABLE_STRIPE_ERRORS = [
    Stripe::APIConnectionError,
    Stripe::APIError,
    Stripe::AuthenticationError,
    Stripe::RateLimitError
  ].freeze

  retry_on(*RETRIABLE_STRIPE_ERRORS, wait: :polynomially_longer, attempts: 3) do |job, error|
    user_id = job.arguments.first[:user_id] || job.arguments.first["user_id"]
    job.log_error("cancel_user_subscription_unrecoverable",
      user_id: user_id,
      error_class: error.class.name,
      error: error.message)
  end

  def perform(user_id:)
    CancelsUserSubscription.call(user_id: user_id)
  end
end
