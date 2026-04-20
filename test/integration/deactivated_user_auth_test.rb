# frozen_string_literal: true

require "test_helper"

# End-to-end coverage that every auth surface rejects a user that
# DeactivatesUser has flipped to active=false. The setup path runs the
# real service so we exercise the email rotation + session/token teardown
# at the same time.
class DeactivatedUserAuthTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @user = users(:one)
    @original_email = @user.email_address
  end

  # --- Surface 1: session cookie ---

  test "session cookie for deactivated user redirects to sign-in" do
    # Sign in first so we have a cookie bound to a real Session row
    post session_path, params: { email_address: @original_email }
    @user.update!(
      auth_token: BCrypt::Password.create("magic"),
      auth_token_expires_at: 30.minutes.from_now
    )

    sign_in_as(@user)
    # Sanity: authenticated now
    get settings_path
    assert_response :success

    # Deactivate (this also destroys all sessions via DeactivatesUser)
    DeactivatesUser.call(user: @user)

    # A stale cookie referencing a destroyed session should fall through
    # the find_session_by_cookie guard and land the caller at sign-in.
    get settings_path
    assert_redirected_to login_path(return_to: "/settings")
  end

  test "session cookie for still-present session of deactivated user is rejected" do
    # Pre-create a Session before deactivation, then simulate the user
    # presenting that cookie after the row somehow survives (defense in depth)
    session = @user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

    # Flip active=false directly WITHOUT destroying sessions, to prove the
    # authentication concern itself rejects deactivated users even if a
    # session row survives.
    @user.update!(active: false)

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end

    get settings_path
    assert_redirected_to login_path(return_to: "/settings")
    # Session row should have been cleaned up by the guard
    assert_nil Session.find_by(id: session.id)
  end

  # --- Surface 2: API bearer token ---

  test "API bearer token for deactivated user returns 401" do
    api_token = GeneratesApiToken.call(user: @user)
    plain = api_token.plain_token

    # Mark user as deactivated WITHOUT revoking the token — proves the
    # base_controller guard fires even if revocation races the deactivation
    @user.update!(active: false)

    get "/api/v1/feed",
      headers: { "Authorization" => "Bearer #{plain}", "Accept" => "application/json" }
    assert_response :unauthorized
  end

  # --- Surface 3: Doorkeeper OAuth token on /mcp ---

  test "Doorkeeper OAuth token for deactivated user returns 401 on /mcp" do
    app = Doorkeeper::Application.create!(
      name: "Deactivation Test Client",
      uid: "deactivation_test",
      redirect_uri: "https://example.com/callback",
      scopes: "podread",
      confidential: true
    )
    token = Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )

    # Flip active=false WITHOUT revoking the token
    @user.update!(active: false)

    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "initialize",
                params: { protocolVersion: "2025-11-25", capabilities: {} } }.to_json,
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "Authorization" => "Bearer #{token.token}"
      }
    assert_response :unauthorized
  end

  # --- Surface 4: Magic-link redeem ---

  test "magic-link redeem for deactivated user returns failure" do
    raw_token = GeneratesAuthToken.call(user: @user)
    @user.update!(active: false)

    result = AuthenticatesMagicLink.call(token: raw_token)

    assert_not result.success?
    assert_nil result.data
  end

  # --- Surface 5: Inbound email to ingest token ---

  test "inbound email for deactivated user does not enqueue processing job" do
    EnablesEmailEpisodes.call(user: @user)
    ingest_address = @user.email_ingest_address

    @user.update!(active: false)

    assert_no_enqueued_jobs(only: ProcessesEmailEpisodeJob) do
      ActionMailbox::InboundEmail.create_and_extract_message_id!(
        Mail.new(
          to: ingest_address,
          from: "sender@example.com",
          subject: "Newsletter",
          body: "A" * 150
        ).to_s
      )
    end
  end

  # --- Surface 6: Episode jobs guard against deactivated users ---

  test "GeneratesEpisodeAudioJob skips when user is deactivated" do
    episode = episodes(:one)
    episode.update!(source_text: "Hello world" * 20, status: :processing)
    episode.user.update!(active: false)

    # Should not raise, should not call GeneratesEpisodeAudio
    Mocktail.replace(GeneratesEpisodeAudio)
    stubs { |m| GeneratesEpisodeAudio.call(episode: m.any) }.with { flunk "should not be called" }

    GeneratesEpisodeAudioJob.perform_now(episode_id: episode.id)

    assert_equal 0, Mocktail.calls(GeneratesEpisodeAudio, :call).size
  ensure
    Mocktail.reset
  end

  test "ProcessesEmailEpisodeJob skips when user is deactivated" do
    episode = episodes(:one)
    episode.update!(source_type: :email, source_text: "A" * 150, status: :processing)
    episode.user.update!(active: false)

    Mocktail.replace(ProcessesEmailEpisode)
    stubs { |m| ProcessesEmailEpisode.call(episode: m.any) }.with { flunk "should not be called" }

    ProcessesEmailEpisodeJob.perform_now(episode_id: episode.id, user_id: episode.user_id)

    assert_equal 0, Mocktail.calls(ProcessesEmailEpisode, :call).size
  ensure
    Mocktail.reset
  end
end
