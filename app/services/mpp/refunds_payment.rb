# frozen_string_literal: true

module Mpp
  class RefundsPayment
    include StructuredLogging

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(mpp_payment:)
      @mpp_payment = mpp_payment
    end

    def call
      return Result.failure("Payment is not in completed status") unless mpp_payment.completed?
      return Result.failure("Payment has no stripe_payment_intent_id") if mpp_payment.stripe_payment_intent_id.blank?

      Stripe::Refund.create(payment_intent: mpp_payment.stripe_payment_intent_id)
      mpp_payment.update!(status: :refunded)

      log_info "mpp_payment_refunded", payment_id: mpp_payment.prefix_id

      Result.success
    # A Stripe error here means real money may be stranded: the Stripe PI was
    # used only to mint a crypto deposit address, funds moved on-chain, and
    # the refund path through Stripe can fail (e.g. the PI hasn't transitioned
    # to succeeded yet because Stripe hasn't observed on-chain settlement).
    # Retries inside a Rails request don't help — the Stripe observation race
    # can last minutes. Persist the failure on the row so a human can recover,
    # and return Result.failure so callers don't treat this as success.
    rescue Stripe::StripeError => e
      log_error "mpp_payment_refund_failed", payment_id: mpp_payment.prefix_id, error: e.message

      mpp_payment.update!(needs_review: true, refund_error: e.message)

      Result.failure(e.message)
    end

    private

    attr_reader :mpp_payment
  end
end
