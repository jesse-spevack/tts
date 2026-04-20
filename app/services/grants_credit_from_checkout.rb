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

    pack = AppConfig::Credits.find_pack_by_price_id(session_price_id)
    return Result.failure("Unknown credit pack price id") unless pack

    GrantsCredits.call(
      user: user,
      amount: pack[:size],
      stripe_session_id: session.id
    )
  end

  private

  attr_reader :session

  def session_price_id
    session.respond_to?(:metadata) && session.metadata&.respond_to?(:price_id) ? session.metadata.price_id : nil
  end
end
