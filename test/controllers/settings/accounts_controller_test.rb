# frozen_string_literal: true

require "test_helper"

module Settings
  class AccountsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      sign_in_as(@user)
    end

    test "destroy soft-deletes the user, signs them out, and redirects" do
      assert_nil @user.deleted_at

      delete settings_account_path

      assert_redirected_to root_path
      assert_not_nil @user.reload.deleted_at
      assert_empty cookies[:session_id].to_s
    end

    test "destroy requires authentication" do
      sign_out

      delete settings_account_path

      assert_redirected_to root_path
    end

    test "destroy is rate-limited: second request within an hour does not soft-delete again" do
      # rate_limit uses Rails.cache; the test env defaults to :null_store
      # (no-op). Swap in a memory store just for this test so the limiter
      # actually tracks state, matching the pattern used elsewhere in this
      # suite (see test/services/checks_audio_circuit_breaker_test.rb).
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new

      delete settings_account_path
      assert_not_nil @user.reload.deleted_at

      # Revive the user so the second hit would otherwise be destructive.
      @user.update_columns(deleted_at: nil)
      sign_in_as(@user)

      delete settings_account_path

      # Rate-limiter tripped: redirected with flash, no second soft-delete.
      assert_redirected_to root_path
      assert_nil @user.reload.deleted_at
    ensure
      Rails.cache = original_cache if original_cache
    end
  end
end
