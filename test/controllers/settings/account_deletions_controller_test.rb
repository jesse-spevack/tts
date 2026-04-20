# frozen_string_literal: true

require "test_helper"

module Settings
  class AccountDeletionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:free_user)

      # Rails 8 `rate_limit` uses Rails.cache; test env defaults to :null_store,
      # which never stores counts so rate-limit tests can't observe the second
      # hit. Swap in a real MemoryStore and restore in teardown.
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    teardown do
      Rails.cache = @original_cache
    end

    # --- new --------------------------------------------------------------

    test "new renders the confirmation page for a signed-in user" do
      sign_in_as(@user)

      get new_settings_account_deletion_path

      assert_response :success
      assert_select "form[action=?][method=?]", settings_account_deletion_path, "post"
      assert_select "input[name=?]", "confirmation"
      assert_includes response.body, @user.email_address
      assert_includes response.body, "DELETE"
    end

    test "new redirects to login when signed out" do
      get new_settings_account_deletion_path

      assert_redirected_to login_path(return_to: "/settings/account_deletion/new")
    end

    # --- create: happy path -----------------------------------------------

    test "create with exact 'DELETE' deactivates the user, resets the session, and redirects to root" do
      sign_in_as(@user)
      original_id = @user.id

      post settings_account_deletion_path, params: { confirmation: "DELETE" }

      assert_redirected_to root_path
      assert_equal "Your account has been deleted.", flash[:notice]

      @user.reload
      assert_equal "deleted-#{original_id}@deleted.invalid", @user.email_address
      assert_not @user.active
      assert_equal 0, @user.sessions.count
    end

    # --- create: wrong word rejection -------------------------------------

    test "create with lowercase 'delete' rerenders new with error and does NOT deactivate" do
      sign_in_as(@user)

      post settings_account_deletion_path, params: { confirmation: "delete" }

      assert_response :unprocessable_entity
      assert_select "form[action=?]", settings_account_deletion_path
      assert @user.reload.active
      assert_not_equal 0, @user.sessions.count
    end

    test "create with blank confirmation rerenders new with error and does NOT deactivate" do
      sign_in_as(@user)

      post settings_account_deletion_path, params: { confirmation: "" }

      assert_response :unprocessable_entity
      assert @user.reload.active
    end

    test "create with typo 'DELET' rerenders new with error and does NOT deactivate" do
      sign_in_as(@user)

      post settings_account_deletion_path, params: { confirmation: "DELET" }

      assert_response :unprocessable_entity
      assert @user.reload.active
    end

    test "create with whitespace-padded 'DELETE' rerenders new with error (strict match)" do
      sign_in_as(@user)

      post settings_account_deletion_path, params: { confirmation: " DELETE " }

      assert_response :unprocessable_entity
      assert @user.reload.active
    end

    # --- create: rate limit -----------------------------------------------

    test "create rate-limits a second request within the window" do
      Mocktail.replace(DeactivatesUser)
      stubs { |m| DeactivatesUser.call(user: m.any) }.with { Result.success(user: @user) }

      sign_in_as(@user)
      post settings_account_deletion_path, params: { confirmation: "DELETE" }
      assert_redirected_to root_path

      # reset_session fired; re-authenticate for the second request.
      sign_in_as(@user)
      post settings_account_deletion_path, params: { confirmation: "DELETE" }

      assert_redirected_to settings_path
      assert_equal "Please try again later.", flash[:alert]
      # Service called exactly once — second request was rate-limited before
      # reaching the action body.
      verify(times: 1) { |m| DeactivatesUser.call(user: m.any) }
    end

    # --- create: service failure ------------------------------------------

    test "create redirects to settings with alert when DeactivatesUser fails" do
      Mocktail.replace(DeactivatesUser)
      stubs { |m| DeactivatesUser.call(user: m.any) }.with { Result.failure("boom") }

      sign_in_as(@user)

      post settings_account_deletion_path, params: { confirmation: "DELETE" }

      assert_redirected_to settings_path
      assert_equal "We couldn't delete your account. Please try again or contact support.", flash[:alert]
      assert @user.reload.active
    end

    # --- create: auth -----------------------------------------------------

    test "create requires authentication" do
      post settings_account_deletion_path, params: { confirmation: "DELETE" }

      assert_redirected_to login_path(return_to: "/settings/account_deletion")
      assert @user.reload.active
    end
  end
end
