class CheckoutController < ApplicationController
  before_action :require_authentication

  # GET /checkout - handles redirects from magic link authentication
  # Validates price_id and redirects to Stripe Checkout
  def show
    return redirect_to(billing_path, alert: "No plan selected") unless params[:price_id].present?
    handle_checkout(params[:price_id])
  end

  def create
    handle_checkout(params[:price_id])
  end

  def success
  end

  def cancel
    redirect_to billing_path
  end

  private

  def handle_checkout(price_id)
    price_result = ValidatesPrice.call(price_id)
    unless price_result.success?
      redirect_to billing_path, alert: price_result.error
      return
    end

    result = CreatesCheckoutSession.call(
      user: Current.user,
      price_id: price_result.data,
      success_url: checkout_success_url,
      cancel_url: checkout_cancel_url
    )

    if result.success?
      redirect_to result.data, allow_other_host: true
    else
      redirect_to billing_path, alert: result.error
    end
  end
end
