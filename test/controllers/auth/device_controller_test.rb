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

    test "show preserves code param through login redirect" do
      get auth_device_path(code: "ABCD-EFGH")

      assert_response :redirect
      assert_redirected_to login_path(return_to: auth_device_path(code: "ABCD-EFGH"))
    end

    test "show renders form when authenticated" do
      sign_in_as(@user)

      get auth_device_path

      assert_response :ok
      assert_select "input[name=code]"
      assert_select "input[type=submit]"
    end

    test "show prefills code from url param" do
      sign_in_as(@user)

      get auth_device_path(code: "ABCD-EFGH")

      assert_response :ok
      assert_select "input[name=code][value='ABCD-EFGH']"
    end

    test "show renders success when confirmed param is true" do
      sign_in_as(@user)

      get auth_device_path(confirmed: "true")

      assert_response :ok
      assert_select "h1", "Device authorized!"
    end

    # POST /auth/device

    test "create redirects to login when not authenticated" do
      post auth_device_path, params: { code: "ABCD-EFGH" }

      assert_response :redirect
      assert_redirected_to login_path(return_to: auth_device_path)
    end

    test "create confirms a valid pending device code and redirects" do
      sign_in_as(@user)
      pending_code = device_codes(:pending)

      post auth_device_path, params: { code: pending_code.user_code }

      assert_redirected_to auth_device_path(confirmed: "true")
      pending_code.reload
      assert pending_code.confirmed?
      assert_equal @user, pending_code.user
    end

    test "create redirects with flash for unknown code" do
      sign_in_as(@user)

      post auth_device_path, params: { code: "XXXX-YYYY" }

      assert_redirected_to auth_device_path
      assert_equal "Code not found. Please check and try again.", flash[:alert]
    end

    test "create redirects with flash for expired code" do
      sign_in_as(@user)
      expired_code = device_codes(:expired)

      post auth_device_path, params: { code: expired_code.user_code }

      assert_redirected_to auth_device_path
      assert flash[:alert].present?
    end

    test "create redirects with flash for already confirmed code" do
      sign_in_as(@user)
      confirmed_code = device_codes(:confirmed)

      post auth_device_path, params: { code: confirmed_code.user_code }

      assert_redirected_to auth_device_path
      assert flash[:alert].present?
    end

    test "create normalizes code without dash" do
      sign_in_as(@user)
      pending_code = device_codes(:pending)
      raw_code = pending_code.user_code.delete("-")

      post auth_device_path, params: { code: raw_code }

      assert_redirected_to auth_device_path(confirmed: "true")
      pending_code.reload
      assert pending_code.confirmed?
    end

    test "create normalizes lowercase code" do
      sign_in_as(@user)
      pending_code = device_codes(:pending)

      post auth_device_path, params: { code: pending_code.user_code.downcase }

      assert_redirected_to auth_device_path(confirmed: "true")
      pending_code.reload
      assert pending_code.confirmed?
    end
  end
end
