# frozen_string_literal: true

class GrantsCreditFromCheckout
  def self.call(session:)
    new(session:).call
  end

  def initialize(session:)
    @session = session
  end

  def call
    user = User.find_by(stripe_customer_id: session.customer)
    return Result.failure("No user found for customer") unless user

    GrantsCredits.call(
      user: user,
      amount: AppConfig::Credits::PACK_SIZE,
      stripe_session_id: session.id
    )
  end

  private

  attr_reader :session
end
