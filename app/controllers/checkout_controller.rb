class CheckoutController < ApplicationController
  before_action :require_authentication

  # GET /checkout - handles redirects from magic link authentication
  # Validates price_id and redirects to Stripe Checkout
  def show
    if params[:pack_size].present?
      return handle_pack_size_checkout(params[:pack_size])
    end

    return redirect_to(billing_path, alert: "No plan selected") unless params[:price_id].present?
    handle_checkout(params[:price_id])
  end

  def create
    if params[:pack_size].present?
      return handle_pack_size_checkout(params[:pack_size])
    end

    handle_checkout(params[:price_id])
  end

  def success
  end

  def cancel
    redirect_to billing_path
  end

  private

  # Accepts a pack size (5/10/20), resolves it to the matching Stripe price_id
  # via AppConfig::Credits::PACKS, then delegates to the price_id checkout path.
  def handle_pack_size_checkout(raw_pack_size)
    pack_result = ResolvesCreditPack.call(raw_pack_size)
    unless pack_result.success?
      redirect_to billing_path, alert: pack_result.error
      return
    end

    handle_checkout(pack_result.data[:stripe_price_id])
  end

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
