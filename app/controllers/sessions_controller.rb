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
    result = SendMagicLink.call(email_address: params[:email_address])

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
    result = AuthenticateMagicLink.call(token: params[:token])

    if result.success?
      start_new_session_for result.data
      redirect_to after_authentication_url, notice: "Welcome back!"
    else
      redirect_to root_path, alert: "Invalid or expired login link. Please try again."
    end
  end
end
