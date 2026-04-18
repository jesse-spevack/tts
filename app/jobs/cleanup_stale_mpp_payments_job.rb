# frozen_string_literal: true

class CleanupStaleMppPaymentsJob < ApplicationJob
  queue_as :default

  def perform
    stale_payments = MppPayment.pending.where("created_at < ?", cutoff_time)
    count = 0

    stale_payments.find_each do |payment|
      cancel_stripe_payment_intent(payment)
      payment.update!(status: :failed)
      count += 1
    end

    Rails.logger.info "[CleanupStaleMppPaymentsJob] Cleaned up #{count} stale pending payments"
  end

  private

  def cutoff_time
    AppConfig::Mpp::CHALLENGE_TTL_SECONDS.seconds.ago
  end

  def cancel_stripe_payment_intent(payment)
    return unless payment.stripe_payment_intent_id.present?

    Stripe::PaymentIntent.cancel(payment.stripe_payment_intent_id)
  rescue Stripe::StripeError => e
    Rails.logger.warn(
      "[CleanupStaleMppPaymentsJob] Failed to cancel PaymentIntent " \
      "#{payment.stripe_payment_intent_id}: #{e.message}"
    )
  end
end
