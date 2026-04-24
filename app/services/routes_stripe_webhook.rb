class RoutesStripeWebhook
  def self.call(event:)
    new(event:).call
  end

  def initialize(event:)
    @event = event
  end

  def call
    case event.type
    when "checkout.session.completed"
      GrantsCreditFromCheckout.call(session: event.data.object)
    else
      Result.success
    end
  end

  private

  attr_reader :event
end
