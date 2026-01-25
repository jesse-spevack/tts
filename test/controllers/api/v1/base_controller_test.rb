require "test_helper"

module Api
  module V1
    class BaseControllerTest < ActionDispatch::IntegrationTest
      # Test authentication via a minimal test controller
      # We'll test the auth behavior by making requests to a V1 endpoint
      # For now, we test the base controller's authentication logic directly

      setup do
        @user = users(:one)
        @api_token = GeneratesApiToken.call(user: @user)
        @plain_token = @api_token.plain_token
      end

      test "authenticate_token! returns 401 when no Authorization header" do
        # Create a test route for this
        with_routing do |set|
          set.draw do
            namespace :api do
              namespace :v1 do
                get "test_auth", to: "test#index"
              end
            end
          end

          get "/api/v1/test_auth", headers: { "Content-Type" => "application/json" }
          assert_response :unauthorized
          assert_equal({ "error" => "Unauthorized" }, response.parsed_body)
        end
      end

      test "authenticate_token! returns 401 when token is invalid" do
        with_routing do |set|
          set.draw do
            namespace :api do
              namespace :v1 do
                get "test_auth", to: "test#index"
              end
            end
          end

          get "/api/v1/test_auth",
            headers: {
              "Content-Type" => "application/json",
              "Authorization" => "Bearer invalid_token_here"
            }
          assert_response :unauthorized
        end
      end

      test "authenticate_token! returns 401 when token is revoked" do
        RevokesApiToken.call(token: @api_token)

        with_routing do |set|
          set.draw do
            namespace :api do
              namespace :v1 do
                get "test_auth", to: "test#index"
              end
            end
          end

          get "/api/v1/test_auth",
            headers: {
              "Content-Type" => "application/json",
              "Authorization" => "Bearer #{@plain_token}"
            }
          assert_response :unauthorized
        end
      end

      test "authenticate_token! succeeds with valid token" do
        with_routing do |set|
          set.draw do
            namespace :api do
              namespace :v1 do
                get "test_auth", to: "test#index"
              end
            end
          end

          get "/api/v1/test_auth",
            headers: {
              "Content-Type" => "application/json",
              "Authorization" => "Bearer #{@plain_token}"
            }
          assert_response :success
        end
      end

      test "authenticate_token! updates last_used_at on successful auth" do
        assert_nil @api_token.last_used_at

        with_routing do |set|
          set.draw do
            namespace :api do
              namespace :v1 do
                get "test_auth", to: "test#index"
              end
            end
          end

          freeze_time do
            get "/api/v1/test_auth",
              headers: {
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{@plain_token}"
              }
            assert_response :success
            @api_token.reload
            assert_equal Time.current, @api_token.last_used_at
          end
        end
      end

      test "authenticate_token! sets current_user from token" do
        with_routing do |set|
          set.draw do
            namespace :api do
              namespace :v1 do
                get "test_auth", to: "test#index"
              end
            end
          end

          get "/api/v1/test_auth",
            headers: {
              "Content-Type" => "application/json",
              "Authorization" => "Bearer #{@plain_token}"
            }
          assert_response :success
          # The test controller returns the current_user's email
          assert_equal @user.email_address, response.parsed_body["user_email"]
        end
      end

      test "authenticate_token! handles malformed Authorization header" do
        with_routing do |set|
          set.draw do
            namespace :api do
              namespace :v1 do
                get "test_auth", to: "test#index"
              end
            end
          end

          get "/api/v1/test_auth",
            headers: {
              "Content-Type" => "application/json",
              "Authorization" => "NotBearer #{@plain_token}"
            }
          assert_response :unauthorized
        end
      end
    end
  end
end

# Minimal test controller for testing base controller auth
module Api
  module V1
    class TestController < BaseController
      def index
        render json: { status: "ok", user_email: current_user.email_address }
      end
    end
  end
end
