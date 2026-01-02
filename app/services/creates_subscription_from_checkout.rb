class CreatesSubscriptionFromCheckout
  def self.call(session:)
    new(session:).call
  end

  def initialize(session:)
    @session = session
  end

  def call
    return Result.failure("No subscription in checkout session") unless session.subscription

    SyncsSubscription.call(stripe_subscription_id: session.subscription)
  end

  private

  attr_reader :session
end
