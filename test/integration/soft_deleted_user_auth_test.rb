# frozen_string_literal: true

require "test_helper"

# Critical acceptance: once a user is soft-deleted (deleted_at set), they
# MUST NOT be able to make authenticated requests into the app via any
# existing auth path. The magic-link path is a special case — we DO let them
# through just far enough to reach /restore_account, per the revive flow.
class SoftDeletedUserAuthTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @user = users(:one)
    @user.update!(deleted_at: Time.current)
  end

  test "magic link sign-in redirects a soft-deleted user to the restore page" do
    token = GeneratesAuthToken.call(user: @user)

    get auth_url, params: { token: token }

    # The magic-link login succeeds and a session is created (the browser
    # now has a valid signed cookie), but the very next authenticated surface
    # they hit — here, the post-login redirect to /episodes/new — bounces
    # them to /restore_account.
    follow_redirect!
    assert_redirected_to new_restore_account_path
  end

  test "session cookie for a soft-deleted user redirects authenticated requests to the restore page" do
    # Realistic flow: user had a live session when they soft-deleted; the
    # cookie is still in the browser. Any authenticated request should now
    # redirect to /restore_account instead of resuming the app.
    @user.update_columns(deleted_at: nil)
    sign_in_as(@user)
    @user.update_columns(deleted_at: Time.current)

    get settings_path

    assert_redirected_to new_restore_account_path
  end

  test "soft-deleted user hitting an authenticated page redirects, never 500s" do
    @user.update_columns(deleted_at: nil)
    sign_in_as(@user)
    @user.update_columns(deleted_at: Time.current)

    get new_episode_path

    assert_response :redirect
    assert_redirected_to new_restore_account_path
  end

  test "API token bearer auth rejects a soft-deleted user" do
    # Revive temporarily so GeneratesApiToken can find the user via the
    # default_scope (it revokes existing tokens via user.api_tokens.active).
    @user.update_columns(deleted_at: nil)
    token = GeneratesApiToken.call(user: @user)
    plain = token.plain_token
    @user.update_columns(deleted_at: Time.current)

    get api_v1_episodes_url, headers: { "Authorization" => "Bearer #{plain}" }

    assert_response :unauthorized
  end

  # An action declared `allow_unauthenticated_access` (e.g. SessionsController#new)
  # MUST still run `redirect_if_soft_deleted` — otherwise the next engineer who
  # adds a side-effecting allow_unauthenticated_access action that touches
  # Current.user introduces a soft-delete bypass.
  test "soft-deleted user with a session cookie hitting an allow_unauthenticated_access action redirects to restore" do
    @user.update_columns(deleted_at: nil)
    sign_in_as(@user)
    @user.update_columns(deleted_at: Time.current)

    # root_url maps to SessionsController#new, which is declared
    # allow_unauthenticated_access.
    get root_url

    assert_redirected_to new_restore_account_path
  end

  # A soft-deleted user with a valid session cookie POSTing to session_url
  # (SessionsController#create, allow_unauthenticated_access) must not be
  # able to trigger the magic-link email flow — they should bounce to the
  # restore page, no email sent.
  test "soft-deleted user POSTing to session_url redirects to restore without sending magic link" do
    @user.update_columns(deleted_at: nil)
    sign_in_as(@user)
    @user.update_columns(deleted_at: Time.current)

    assert_no_enqueued_emails do
      post session_url, params: { email_address: @user.email_address }
    end

    assert_redirected_to new_restore_account_path
  end

  test "Doorkeeper access token for a soft-deleted user is rejected at MCP endpoint" do
    app = Doorkeeper::Application.create!(
      name: "probe",
      uid: "soft_deleted_probe",
      redirect_uri: "https://example.com/cb",
      scopes: "podread",
      confidential: false
    )
    token = Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )

    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "initialize" }.to_json,
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "Authorization" => "Bearer #{token.token}"
      }

    assert_response :unauthorized
  end
end
