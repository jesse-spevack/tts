require "test_helper"

module Auth
  class DeviceControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
    end

    # GET /auth/device

    test "show redirects to login when not authenticated" do
      get auth_device_path

      assert_response :redirect
      assert_redirected_to login_path(return_to: auth_device_path)
    end

    test "show renders form when authenticated" do
      sign_in_as(@user)

      get auth_device_path

      assert_response :ok
      assert_select "input[name=code]"
      assert_select "input[type=submit]"
    end

    # POST /auth/device

    test "create redirects to login when not authenticated" do
      post auth_device_path, params: { code: "ABCD-EFGH" }

      assert_response :redirect
      assert_redirected_to login_path(return_to: auth_device_path)
    end

    test "create confirms a valid pending device code" do
      sign_in_as(@user)
      pending_code = device_codes(:pending)

      post auth_device_path, params: { code: pending_code.user_code }

      assert_response :ok
      pending_code.reload
      assert pending_code.confirmed?
      assert_equal @user, pending_code.user
    end

    test "create shows error for unknown code" do
      sign_in_as(@user)

      post auth_device_path, params: { code: "XXXX-YYYY" }

      assert_response :unprocessable_entity
    end

    test "create shows error for expired code" do
      sign_in_as(@user)
      expired_code = device_codes(:expired)

      post auth_device_path, params: { code: expired_code.user_code }

      assert_response :unprocessable_entity
    end

    test "create shows error for already confirmed code" do
      sign_in_as(@user)
      confirmed_code = device_codes(:confirmed)

      post auth_device_path, params: { code: confirmed_code.user_code }

      assert_response :unprocessable_entity
    end

    test "create normalizes code without dash" do
      sign_in_as(@user)
      pending_code = device_codes(:pending)
      # Send code without the dash
      raw_code = pending_code.user_code.delete("-")

      post auth_device_path, params: { code: raw_code }

      assert_response :ok
      pending_code.reload
      assert pending_code.confirmed?
    end

    test "create normalizes lowercase code" do
      sign_in_as(@user)
      pending_code = device_codes(:pending)

      post auth_device_path, params: { code: pending_code.user_code.downcase }

      assert_response :ok
      pending_code.reload
      assert pending_code.confirmed?
    end
  end
end
