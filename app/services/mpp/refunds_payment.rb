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
    rescue Stripe::StripeError => e
      log_error "mpp_payment_refund_failed", payment_id: mpp_payment.prefix_id, error: e.message

      Result.failure(e.message)
    end

    private

    attr_reader :mpp_payment
  end
end
