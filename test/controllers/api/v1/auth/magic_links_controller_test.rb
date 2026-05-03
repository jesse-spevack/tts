require "test_helper"

module Api
  module V1
    module Auth
      class MagicLinksControllerTest < ActionDispatch::IntegrationTest
        setup do
          # Rails 8 `rate_limit` uses Rails.cache; clear the per-IP counter so
          # state doesn't leak across tests in the same process.
          Rails.cache.clear
        end

        test "valid email returns 200 and invokes SendsMagicLink" do
          Mocktail.replace(SendsMagicLink)
          stubs { |m| SendsMagicLink.call(email_address: m.any) }.with { Result.success(users(:one)) }

          post api_v1_auth_magic_links_path,
            params: { email_address: "test@example.com" },
            as: :json

          assert_response :ok
          assert_equal true, response.parsed_body["ok"]
          verify(times: 1) { SendsMagicLink.call(email_address: "test@example.com") }
        end

        test "strips whitespace from email before validating and dispatching" do
          Mocktail.replace(SendsMagicLink)
          stubs { |m| SendsMagicLink.call(email_address: m.any) }.with { Result.success(users(:one)) }

          post api_v1_auth_magic_links_path,
            params: { email_address: "  test@example.com  " },
            as: :json

          assert_response :ok
          verify(times: 1) { SendsMagicLink.call(email_address: "test@example.com") }
        end

        test "invalid email format returns 422 and does not invoke SendsMagicLink" do
          Mocktail.replace(SendsMagicLink)

          post api_v1_auth_magic_links_path,
            params: { email_address: "not-an-email" },
            as: :json

          assert_response :unprocessable_entity
          assert_equal "invalid_email", response.parsed_body["error"]
          verify(times: 0) { |m| SendsMagicLink.call(email_address: m.any) }
        end

        test "blank email returns 422 and does not invoke SendsMagicLink" do
          Mocktail.replace(SendsMagicLink)

          post api_v1_auth_magic_links_path,
            params: { email_address: "" },
            as: :json

          assert_response :unprocessable_entity
          assert_equal "invalid_email", response.parsed_body["error"]
          verify(times: 0) { |m| SendsMagicLink.call(email_address: m.any) }
        end

        test "missing email param returns 422 and does not invoke SendsMagicLink" do
          Mocktail.replace(SendsMagicLink)

          post api_v1_auth_magic_links_path, params: {}, as: :json

          assert_response :unprocessable_entity
          assert_equal "invalid_email", response.parsed_body["error"]
          verify(times: 0) { |m| SendsMagicLink.call(email_address: m.any) }
        end

        test "rate-limits the 11th request within the window" do
          Mocktail.replace(SendsMagicLink)
          stubs { |m| SendsMagicLink.call(email_address: m.any) }.with { Result.success(users(:one)) }

          10.times do
            post api_v1_auth_magic_links_path,
              params: { email_address: "test@example.com" },
              as: :json
            assert_response :ok
          end

          post api_v1_auth_magic_links_path,
            params: { email_address: "test@example.com" },
            as: :json

          assert_response :too_many_requests
          assert_equal "rate_limited", response.parsed_body["error"]
          # Service called exactly 10 times — the 11th request was rate-limited
          # before reaching the action body.
          verify(times: 10) { |m| SendsMagicLink.call(email_address: m.any) }
        end
      end
    end
  end
end
