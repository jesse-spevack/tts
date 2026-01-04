# frozen_string_literal: true

class TestHelpersController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection
  before_action :ensure_local_environment

  # GET /test/magic_link_token/:email
  # Returns a fresh magic link token for the given email.
  # The token still needs to go through normal auth flow.
  def magic_link_token
    user = User.find_by!(email_address: params[:email])
    token = GeneratesAuthToken.call(user: user)
    render json: { token: token, email: params[:email] }
  end

  # POST /test/create_user
  # Creates a new test user. Email should match pattern *@test.example.com
  # for easy cleanup via rake task.
  def create_user
    email = params[:email]

    unless email&.end_with?("@test.example.com")
      return render json: { error: "Email must end with @test.example.com" }, status: :unprocessable_entity
    end

    user = User.find_or_create_by!(email_address: email)
    token = GeneratesAuthToken.call(user: user)
    render json: { token: token, email: email, user_id: user.id }
  end

  private

  def ensure_local_environment
    raise ActionController::RoutingError, "Not Found" unless Rails.env.local?
  end
end
