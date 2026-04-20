# frozen_string_literal: true

require "test_helper"

# End-to-end journey for the typed-DELETE confirmation flow: from Settings,
# through the confirmation page, to a deactivated+signed-out state. Rails
# system tests aren't used in this repo (see empty test/system/), so this is
# an integration test instead of a browser-driven system test — same coverage
# for a flow with no meaningful JS behavior.
class AccountDeletionFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:free_user)
    @original_id = @user.id
    @original_email = @user.email_address

    # Clear the shared rate-limit counter — AccountDeletionsController caps
    # #create at 1/hour per user, and Rails.cache leaks across tests in the
    # same process (even when it proxies :null_store, Rails 8 rate_limit
    # keeps a live counter on the proxied store).
    Rails.cache.clear
  end

  test "settings page delete link navigates to confirmation page, not a turbo-confirm modal" do
    sign_in_as(@user)

    get settings_path
    assert_response :success

    # Link, not button_to with _method=delete
    assert_select "a[href=?]", new_settings_account_deletion_path, text: "Delete account"
    # turbo_confirm left over anywhere? (regression guard)
    assert_select "[data-turbo-confirm]", false
    assert_select "section#account input[name=_method][value=delete]", false
  end

  test "typing the wrong word rerenders the form with an error and preserves the account" do
    sign_in_as(@user)

    get new_settings_account_deletion_path
    assert_response :success
    assert_includes response.body, @original_email

    post settings_account_deletion_path, params: { confirmation: "delete" }
    assert_response :unprocessable_entity
    assert_select "form[action=?]", settings_account_deletion_path
    assert_match(/Please type DELETE/i, response.body)

    @user.reload
    assert @user.active, "user should still be active after wrong-word submission"
    assert_equal @original_email, @user.email_address
  end

  test "typing DELETE deactivates the account, signs the user out, and locks them out of settings" do
    sign_in_as(@user)

    get new_settings_account_deletion_path
    assert_response :success

    post settings_account_deletion_path, params: { confirmation: "DELETE" }
    assert_redirected_to root_path
    assert_equal "Your account has been deleted.", flash[:notice]

    # DB state: anonymize-in-place
    @user.reload
    assert_not @user.active
    assert_equal "deleted-#{@original_id}@deleted.invalid", @user.email_address
    assert_equal 0, @user.sessions.count

    # Signed-out: visiting a protected page bounces to login
    get settings_path
    assert_redirected_to login_path(return_to: "/settings")
  end
end
