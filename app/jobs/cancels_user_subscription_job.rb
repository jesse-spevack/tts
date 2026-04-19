# frozen_string_literal: true

# Async wrapper around CancelsUserSubscription. Enqueued from
# SoftDeletesUser so the local soft-delete commits immediately and Stripe
# cleanup retries on its own. Retry + logging live here; the business logic
# lives in the service.
class CancelsUserSubscriptionJob < ApplicationJob
  include StructuredLogging

  queue_as :default

  # Block-form retry_on so exhausted retries surface as log_error (Sentry per
  # project convention). Without this the job DLQs silently and Stripe keeps
  # billing through the outage.
  retry_on Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.log_error("cancel_user_subscription_unrecoverable",
      user_id: job.arguments.first[:user_id],
      error_class: error.class.name,
      error: error.message)
  end

  retry_on Stripe::APIError, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.log_error("cancel_user_subscription_unrecoverable",
      user_id: job.arguments.first[:user_id],
      error_class: error.class.name,
      error: error.message)
  end

  def perform(user_id:)
    CancelsUserSubscription.call(user_id: user_id)
  end
end
