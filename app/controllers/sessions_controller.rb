class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to root_path, alert: "Try again later." }

  def new
    # Redirect authenticated users to episode creation form
    return redirect_to new_episode_path if authenticated?

    # If accessed with a token (from magic link), authenticate
    if params[:token].present?
      authenticate_with_token
    end
  end

  def create
    result = SendsMagicLink.call(email_address: params[:email_address], plan: params[:plan])

    if result.success?
      redirect_to root_path, notice: "Check your email for a login link!"
    else
      redirect_to root_path, alert: "Please enter a valid email address."
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other, notice: "You've been logged out."
  end

  private

  def authenticate_with_token
    result = AuthenticatesMagicLink.call(token: params[:token])

    if result.success?
      start_new_session_for result.data
      # Skip flash message when redirecting to checkout - the checkout success page has its own welcome message
      if checkout_flow?(params[:plan])
        redirect_to post_login_path(params[:plan])
      else
        redirect_to post_login_path(params[:plan]), notice: "Welcome back!"
      end
    else
      redirect_to root_path, alert: "Invalid or expired login link. Please try again."
    end
  end

  PLAN_PRICES = {
    "premium_monthly" => AppConfig::Stripe::PRICE_ID_MONTHLY,
    "premium_annual"  => AppConfig::Stripe::PRICE_ID_ANNUAL,
    "credit_pack"     => AppConfig::Stripe::PRICE_ID_CREDIT_PACK,
  }.freeze

  def checkout_flow?(plan)
    PLAN_PRICES.key?(plan)
  end

  def post_login_path(plan)
    if (price_id = PLAN_PRICES[plan])
      checkout_path(price_id: price_id)
    else
      after_authentication_url
    end
  end
end
