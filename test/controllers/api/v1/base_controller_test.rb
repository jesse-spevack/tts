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

      # === Doorkeeper OAuth token fallback ===

      test "authenticate_token! succeeds with valid Doorkeeper token" do
        app = Doorkeeper::Application.create!(
          name: "Test OAuth App",
          uid: "test_oauth",
          redirect_uri: "https://example.com/callback",
          scopes: "podread",
          confidential: true
        )
        doorkeeper_token = Doorkeeper::AccessToken.create!(
          application: app,
          resource_owner_id: @user.id,
          scopes: "podread",
          expires_in: 1.hour
        )

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
              "Authorization" => "Bearer #{doorkeeper_token.token}"
            }
          assert_response :success
          assert_equal @user.email_address, response.parsed_body["user_email"]
        end
      end

      test "authenticate_token! rejects revoked Doorkeeper token" do
        app = Doorkeeper::Application.create!(
          name: "Test OAuth App",
          uid: "test_oauth_revoked",
          redirect_uri: "https://example.com/callback",
          scopes: "podread",
          confidential: true
        )
        doorkeeper_token = Doorkeeper::AccessToken.create!(
          application: app,
          resource_owner_id: @user.id,
          scopes: "podread",
          expires_in: 1.hour
        )
        doorkeeper_token.revoke

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
              "Authorization" => "Bearer #{doorkeeper_token.token}"
            }
          assert_response :unauthorized
        end
      end

      test "authenticate_token! rejects expired Doorkeeper token" do
        app = Doorkeeper::Application.create!(
          name: "Test OAuth App",
          uid: "test_oauth_expired",
          redirect_uri: "https://example.com/callback",
          scopes: "podread",
          confidential: true
        )
        doorkeeper_token = Doorkeeper::AccessToken.create!(
          application: app,
          resource_owner_id: @user.id,
          scopes: "podread",
          expires_in: 0,
          created_at: 2.hours.ago
        )

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
              "Authorization" => "Bearer #{doorkeeper_token.token}"
            }
          assert_response :unauthorized
        end
      end

      test "authenticate_token! rejects deactivated user's API token" do
        @user.update!(active: false)

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

      test "authenticate_token! rejects Doorkeeper token for deactivated user" do
        app = Doorkeeper::Application.create!(
          name: "Test OAuth App",
          uid: "test_oauth_deactivated",
          redirect_uri: "https://example.com/callback",
          scopes: "podread",
          confidential: true
        )
        doorkeeper_token = Doorkeeper::AccessToken.create!(
          application: app,
          resource_owner_id: @user.id,
          scopes: "podread",
          expires_in: 1.hour
        )
        @user.update!(active: false)

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
              "Authorization" => "Bearer #{doorkeeper_token.token}"
            }
          assert_response :unauthorized
        end
      end

      test "authenticate_token! prefers API token over Doorkeeper token" do
        # If a token matches both an API token and a Doorkeeper token,
        # the API token should win (preserves backwards compatibility)
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
          # Verify it used the API token path (last_used_at is updated)
          @api_token.reload
          assert_not_nil @api_token.last_used_at
        end
      end

      # === Structured logging (token_prefix) ===

      test "successful PAT auth logs token_prefix in structured log payload" do
        logs = capture_logs do
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

        assert_match(/event=api_request_authenticated/, logs)
        assert_match(/api_token_prefix=#{Regexp.escape(@api_token.token_prefix)}/, logs)
      end

      test "token_digest never appears in logs on successful auth" do
        logs = capture_logs do
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
          end
        end

        assert_no_match(/token_digest/, logs)
        assert_no_match(/#{Regexp.escape(@api_token.token_digest)}/, logs)
      end

      test "token_digest never appears in logs on failed auth" do
        logs = capture_logs do
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

        assert_no_match(/token_digest/, logs)
      end

      test "api_token_prefix does not leak across sequential requests" do
        # Guards against Current attribute leakage in threaded servers:
        # after an authed request as user A, a subsequent unauth request
        # must not see A's prefix in logs.
        logs = capture_logs do
          with_routing do |set|
            set.draw do
              namespace :api do
                namespace :v1 do
                  get "test_auth", to: "test#index"
                end
              end
            end

            # Authed request — should log A's prefix
            get "/api/v1/test_auth",
              headers: {
                "Content-Type" => "application/json",
                "Authorization" => "Bearer #{@plain_token}"
              }
            assert_response :success

            # Sequential unauth request on the same test session
            get "/api/v1/test_auth",
              headers: { "Content-Type" => "application/json" }
            assert_response :unauthorized
          end
        end

        # A's prefix should appear once (first request) — never again
        prefix_pattern = /api_token_prefix=#{Regexp.escape(@api_token.token_prefix)}/
        assert_equal 1, logs.scan(prefix_pattern).count,
          "api_token_prefix must appear exactly once across a PAT request + unauth request sequence"
      end

      test "unauthenticated requests do not emit api_token_prefix in logs" do
        logs = capture_logs do
          with_routing do |set|
            set.draw do
              namespace :api do
                namespace :v1 do
                  get "test_auth", to: "test#index"
                end
              end
            end

            get "/api/v1/test_auth",
              headers: { "Content-Type" => "application/json" }
            assert_response :unauthorized
          end
        end

        assert_no_match(/api_token_prefix=/, logs)
        assert_no_match(/event=api_request_authenticated/, logs)
      end

      test "Doorkeeper OAuth auth does not emit api_token_prefix in logs" do
        app = Doorkeeper::Application.create!(
          name: "Test OAuth App",
          uid: "test_oauth_log",
          redirect_uri: "https://example.com/callback",
          scopes: "podread",
          confidential: true
        )
        doorkeeper_token = Doorkeeper::AccessToken.create!(
          application: app,
          resource_owner_id: @user.id,
          scopes: "podread",
          expires_in: 1.hour
        )

        logs = capture_logs do
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
                "Authorization" => "Bearer #{doorkeeper_token.token}"
              }
            assert_response :success
          end
        end

        assert_no_match(/api_token_prefix=/, logs)
        assert_no_match(/event=api_request_authenticated/, logs)
      end

      private

      def capture_logs
        output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = Logger.new(output)
        yield
        output.string
      ensure
        Rails.logger = original_logger
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
