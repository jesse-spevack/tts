# frozen_string_literal: true

require "test_helper"

class RestoreAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(deleted_at: 2.days.ago)
  end

  test "new renders confirmation page when signed-in user is soft-deleted" do
    sign_in_as(@user)

    get new_restore_account_path

    assert_response :success
    assert_select "h1", text: /welcome back/i
  end

  test "new redirects to root when not authenticated" do
    get new_restore_account_path

    assert_redirected_to root_path
  end

  test "new redirects to episodes when signed-in user is NOT soft-deleted" do
    sign_in_as(users(:two))

    get new_restore_account_path

    assert_redirected_to new_episode_path
  end

  test "create restores the user and signs them in" do
    sign_in_as(@user)

    post restore_account_path

    @user.reload
    assert_nil @user.deleted_at
    assert_redirected_to new_episode_path
    assert_match(/welcome back/i, flash[:notice])
  end

  test "create is a no-op when user is already restored" do
    # Sign in while soft-deleted (that's the only state restore_account is
    # reachable from). If somehow a race un-deleted the row, we should still
    # not blow up.
    sign_in_as(@user)
    @user.update!(deleted_at: nil)

    post restore_account_path

    assert_redirected_to new_episode_path
  end
end
