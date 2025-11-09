class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
    # If accessed with a token (from magic link), authenticate
    if params[:token].present?
      authenticate_with_token
    end
  end

  def create
    send_magic_link
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other, notice: "You've been logged out."
  end

  private

  def authenticate_with_token
    user = User.find_by(auth_token: params[:token])
    if user&.auth_token_valid?
      start_new_session_for user
      user.update!(auth_token: nil, auth_token_expires_at: nil) # Invalidate token after use
      redirect_to after_authentication_url, notice: "Welcome back!"
    else
      redirect_to new_session_path, alert: "Invalid or expired login link. Please try again."
    end
  end

  def send_magic_link
    user = User.find_or_create_by(email_address: params[:email_address])
    if user.persisted?
      user.generate_auth_token!
      SessionsMailer.magic_link(user).deliver_later
      redirect_to new_session_path, notice: "Check your email for a login link!"
    else
      redirect_to new_session_path, alert: "Please enter a valid email address."
    end
  end
end
