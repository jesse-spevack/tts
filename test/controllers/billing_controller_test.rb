require "test_helper"

class BillingControllerTest < ActionDispatch::IntegrationTest
  include SessionTestHelper

  test "show requires authentication" do
    get billing_path
    assert_redirected_to login_path(return_to: "/billing")
  end

  test "show renders for free user (iny7: no upgrade redirect)" do
    # Pre-iny7 free users got bounced to /upgrade. After iny7 there is no
    # /upgrade; free users stay on /billing.
    sign_in_as(users(:free_user))
    get billing_path
    assert_response :success
  end

  test "show renders for complimentary user" do
    sign_in_as(users(:complimentary_user))
    get billing_path
    assert_response :success
  end

  test "show renders for unlimited user" do
    sign_in_as(users(:unlimited_user))
    get billing_path
    assert_response :success
  end

  # --- Free + Credits card pluralization (agent-team-01q.5) ---

  test "Free + Credits card pluralizes 'episode credit' for balance of 1" do
    user = users(:credit_user)
    user.credit_balance.update!(balance: 1)
    sign_in_as(user)

    get billing_path

    assert_response :success
    assert_select "*", text: /1 episode credit remaining/
    # Plural form must NOT appear for a balance of 1.
    assert_select "*", text: /1 episode credits remaining/, count: 0
  end

  test "Free + Credits card uses plural 'episode credits' for balance of 2" do
    user = users(:credit_user)
    user.credit_balance.update!(balance: 2)
    sign_in_as(user)

    get billing_path

    assert_response :success
    assert_select "*", text: /2 episode credits remaining/
  end
end
