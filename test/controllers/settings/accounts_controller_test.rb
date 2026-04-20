# frozen_string_literal: true

require "test_helper"

module Settings
  class AccountsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:free_user)
      sign_in_as(@user)

      # Rails 8 `rate_limit` uses Rails.cache; test env defaults to :null_store,
      # which never stores counts so rate-limit tests can't observe the second
      # hit. Swap in a real MemoryStore and restore in teardown.
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    teardown do
      Rails.cache = @original_cache
    end

    test "destroy deactivates the user, resets the session, and redirects to root with notice" do
      original_id = @user.id

      delete settings_account_path

      assert_redirected_to root_path
      assert_equal "Your account has been deleted.", flash[:notice]

      @user.reload
      assert_equal "deleted-#{original_id}@deleted.invalid", @user.email_address
      assert_not @user.active
      # Session was reset — DeactivatesUser destroys all Session rows, and the
      # controller calls reset_session so the cookie jar is cleared too.
      assert_equal 0, @user.sessions.count
    end

    test "destroy rate-limits a second request within the window" do
      # Stub DeactivatesUser so the first request does not reset the session or
      # mutate the user — we want to isolate the rate_limit behavior. With the
      # stub returning success, the controller resets the session and redirects,
      # so we have to re-sign-in before the second request. With the stub
      # returning failure, the controller only redirects — session stays intact.
      Mocktail.replace(DeactivatesUser)
      stubs { |m| DeactivatesUser.call(user: m.any) }.with { Result.success(user: @user) }

      delete settings_account_path
      assert_redirected_to root_path

      # Re-authenticate for the second request; reset_session fired on the first.
      sign_in_as(@user)

      delete settings_account_path

      assert_redirected_to settings_path
      assert_equal "Please try again later.", flash[:alert]
      # Service was called exactly once — the second request was rate-limited
      # before reaching the action body.
      verify(times: 1) { |m| DeactivatesUser.call(user: m.any) }
    end

    test "destroy requires authentication" do
      sign_out

      delete settings_account_path

      assert_redirected_to login_path(return_to: "/settings/account")
    end

    test "destroy redirects to settings with alert when DeactivatesUser fails" do
      Mocktail.replace(DeactivatesUser)
      stubs { |m| DeactivatesUser.call(user: m.any) }.with { Result.failure("boom") }

      delete settings_account_path

      assert_redirected_to settings_path
      assert_equal "We couldn't delete your account. Please try again or contact support.", flash[:alert]
      # User should remain active since the service reported failure.
      assert @user.reload.active
    end
  end
end
