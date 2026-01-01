class CreatesBillingPortalSession
  def self.call(stripe_customer_id:, return_url:)
    new(stripe_customer_id:, return_url:).call
  end

  def initialize(stripe_customer_id:, return_url:)
    @stripe_customer_id = stripe_customer_id
    @return_url = return_url
  end

  def call
    session = Stripe::BillingPortal::Session.create(
      customer: stripe_customer_id,
      return_url: return_url
    )
    Result.success(session.url)
  rescue Stripe::StripeError => e
    Result.failure("Stripe error: #{e.message}")
  end

  private

  attr_reader :stripe_customer_id, :return_url
end
