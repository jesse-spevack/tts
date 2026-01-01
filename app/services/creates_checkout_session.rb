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
    customer_id = find_or_create_customer_id
    session = create_checkout_session(customer_id)
    Result.success(session.url)
  rescue Stripe::StripeError => e
    Result.failure("Stripe error: #{e.message}")
  end

  private

  attr_reader :user, :price_id, :success_url, :cancel_url

  def find_or_create_customer_id
    return user.stripe_customer_id if user.stripe_customer_id.present?

    customer = find_existing_customer || create_customer
    user.update!(stripe_customer_id: customer.id)
    customer.id
  end

  def find_existing_customer
    result = Stripe::Customer.list(email: user.email_address, limit: 1)
    result.data.first
  end

  def create_customer
    Stripe::Customer.create(
      email: user.email_address,
      metadata: { user_id: user.id }
    )
  end

  def create_checkout_session(customer_id)
    Stripe::Checkout::Session.create(
      customer: customer_id,
      mode: "subscription",
      line_items: [ { price: price_id, quantity: 1 } ],
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: { user_id: user.id }
    )
  end
end
