# frozen_string_literal: true

class TestHelpersController < ApplicationController
  before_action :ensure_local_environment

  # GET /test/magic_link_token/:email
  # Returns a fresh magic link token for the given email.
  # The token still needs to go through normal auth flow.
  def magic_link_token
    user = User.find_by!(email_address: params[:email])
    token = GenerateAuthToken.call(user: user)
    render json: { token: token, email: params[:email] }
  end

  private

  def ensure_local_environment
    raise ActionController::RoutingError, "Not Found" unless Rails.env.local?
  end
end
