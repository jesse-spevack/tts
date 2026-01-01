class CreatesCheckoutSession
  def self.call(user:, price_id:, success_url:, cancel_url:)
    new(user:, price_id:, success_url:, cancel_url:).call
  end

  def initialize(user:, price_id:, success_url:, cancel_url:)
    @user = user
    @price_id = price_id
    @success_url = success_url
    @cancel_url = cancel_url
  end

  def call
    customer = find_or_create_customer
    session = create_checkout_session(customer)
    Result.success(session.url)
  rescue Stripe::StripeError => e
    Result.failure("Stripe error: #{e.message}")
  end

  private

  attr_reader :user, :price_id, :success_url, :cancel_url

  def find_or_create_customer
    existing = Stripe::Customer.list(email: user.email_address, limit: 1)
    return existing.data.first if existing.data.any?

    Stripe::Customer.create(
      email: user.email_address,
      metadata: { user_id: user.id }
    )
  end

  def create_checkout_session(customer)
    Stripe::Checkout::Session.create(
      customer: customer.id,
      mode: "subscription",
      line_items: [{ price: price_id, quantity: 1 }],
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: { user_id: user.id }
    )
  end
end
