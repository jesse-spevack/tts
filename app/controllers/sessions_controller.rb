class SessionsController < ApplicationController
  # Thin proxy around Rails.cache so the rate_limit store is resolved at
  # request time. Rails 8 `rate_limit` captures `store:` at class-load via
  # the `cache_store` default, and the test env default is :null_store
  # (no-op). The proxy lets tests swap Rails.cache to MemoryStore to exercise
  # the limiter — same pattern as Settings::AccountsController.
  class MagicLinkRateLimitStore
    def increment(*args, **kwargs) = Rails.cache.increment(*args, **kwargs)
  end

  allow_unauthenticated_access only: %i[ new create ]
  # A soft-deleted user lands on /restore_account; from there they may click
  # Sign out. That hits #destroy and needs to bypass the soft-delete redirect.
  allow_soft_deleted_access only: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to root_path, alert: "Try again later." }
  # Per-email magic-link rate limit. Threat model: SendsMagicLink intentionally
  # reaches soft-deleted users (Option C revive flow), which means an attacker
  # who knows a deleted email can spam its inbox. This limit applies to ALL
  # users, not just soft-deleted, as orthogonal mailbox-spam mitigation.
  rate_limit to: 5,
             within: 1.hour,
             by: -> {
               # Mirror User.normalizes :email_address (strip + downcase). Reject
               # non-String shapes (e.g. param-pollution arrays) so they collide
               # into one bucket instead of a junk per-shape key. Blank/missing
               # emails also share the empty bucket — SendsMagicLink rejects
               # those anyway, so the bucket only protects against accidental
               # spam from a buggy client.
               raw = params[:email_address]
               raw.is_a?(String) ? raw.strip.downcase : ""
             },
             store: MagicLinkRateLimitStore.new,
             with: -> { redirect_to root_path, alert: "Please wait before requesting another login link." },
             only: :create

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

  def checkout_flow?(plan)
    plan.in?(%w[premium_monthly premium_annual credit_pack])
  end

  def post_login_path(plan)
    case plan
    when "premium_monthly"
      checkout_path(price_id: AppConfig::Stripe::PRICE_ID_MONTHLY)
    when "premium_annual"
      checkout_path(price_id: AppConfig::Stripe::PRICE_ID_ANNUAL)
    when "credit_pack"
      checkout_path(price_id: AppConfig::Stripe::PRICE_ID_CREDIT_PACK)
    else
      after_authentication_url
    end
  end
end
