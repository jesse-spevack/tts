# frozen_string_literal: true

class GrantsCreditFromCheckout
  include StructuredLogging

  def self.call(session:)
    new(session:).call
  end

  def initialize(session:)
    @session = session
  end

  def call
    user = User.find_by(stripe_customer_id: session.customer)

    unless user
      # Most common cause today: user soft-deleted between paying and webhook
      # delivery. Silent failure here leaves the charge unreconciled — log
      # loud so finance can spot it.
      log_error "grants_credit_no_user",
        stripe_customer_id: session.customer,
        stripe_session_id: session.id
      return Result.failure("No user found for customer")
    end

    GrantsCredits.call(
      user: user,
      amount: AppConfig::Credits::PACK_SIZE,
      stripe_session_id: session.id
    )
  end

  private

  attr_reader :session
end
