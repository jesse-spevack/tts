class CreatesBillingPortalSession
  def self.call(user:, return_url:)
    new(user:, return_url:).call
  end

  def initialize(user:, return_url:)
    @user = user
    @return_url = return_url
  end

  def call
    return Result.failure("No Stripe customer ID") unless user.stripe_customer_id.present?

    session = Stripe::BillingPortal::Session.create(
      customer: user.stripe_customer_id,
      return_url: return_url
    )
    Result.success(session.url)
  rescue Stripe::StripeError => e
    Result.failure("Stripe error: #{e.message}")
  end

  private

  attr_reader :user, :return_url
end
