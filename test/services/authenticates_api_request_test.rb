require "test_helper"

class AuthenticatesApiRequestTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @api_token = GeneratesApiToken.call(user: @user)
    @plain_token = @api_token.plain_token
  end

  teardown do
    Current.reset
  end

  # === API token happy path ===

  test "call with valid API token returns success with user, source, and api_token" do
    result = AuthenticatesApiRequest.call(bearer: @plain_token)

    assert result.success?
    assert_equal @user, result.data[:user]
    assert_equal "api_token", result.data[:source]
    assert_equal @api_token.id, result.data[:api_token].id
  end

  test "call with valid API token touches last_used_at" do
    assert_nil @api_token.last_used_at

    freeze_time do
      AuthenticatesApiRequest.call(bearer: @plain_token)
      @api_token.reload
      assert_equal Time.current, @api_token.last_used_at
    end
  end

  test "call with valid API token sets Current.api_token_prefix" do
    AuthenticatesApiRequest.call(bearer: @plain_token)
    assert_equal @api_token.token_prefix, Current.api_token_prefix
  end

  test "call with valid API token logs api_request_authenticated with user_id and source" do
    logs = capture_logs do
      AuthenticatesApiRequest.call(bearer: @plain_token)
    end

    assert_match(/event=api_request_authenticated/, logs)
    assert_match(/user_id=#{@user.id}/, logs)
    assert_match(/source=#{@api_token.source}/, logs)
  end

  # === Doorkeeper happy path ===

  test "call with valid Doorkeeper token returns success with source oauth and nil api_token" do
    doorkeeper_token = create_doorkeeper_token(uid: "oauth_valid")

    result = AuthenticatesApiRequest.call(bearer: doorkeeper_token.token)

    assert result.success?
    assert_equal @user, result.data[:user]
    assert_equal "oauth", result.data[:source]
    assert_nil result.data[:api_token]
  end

  test "call with valid Doorkeeper token does not set Current.api_token_prefix" do
    doorkeeper_token = create_doorkeeper_token(uid: "oauth_no_prefix")

    AuthenticatesApiRequest.call(bearer: doorkeeper_token.token)
    assert_nil Current.api_token_prefix
  end

  test "call with valid Doorkeeper token does not emit api_request_authenticated" do
    doorkeeper_token = create_doorkeeper_token(uid: "oauth_no_log")

    logs = capture_logs do
      AuthenticatesApiRequest.call(bearer: doorkeeper_token.token)
    end

    assert_no_match(/event=api_request_authenticated/, logs)
  end

  # === Missing / malformed bearer ===

  test "call with nil bearer returns failure with code :unauthorized" do
    result = AuthenticatesApiRequest.call(bearer: nil)

    assert result.failure?
    assert_equal :unauthorized, result.code
    assert_equal "Unauthorized", result.error
  end

  test "call with blank bearer returns failure" do
    result = AuthenticatesApiRequest.call(bearer: "")

    assert result.failure?
    assert_equal :unauthorized, result.code
  end

  # === Invalid tokens ===

  test "call with invalid token returns failure" do
    result = AuthenticatesApiRequest.call(bearer: "invalid_token_here")

    assert result.failure?
    assert_equal :unauthorized, result.code
  end

  test "call with revoked API token returns failure" do
    RevokesApiToken.call(token: @api_token)

    result = AuthenticatesApiRequest.call(bearer: @plain_token)

    assert result.failure?
    assert_equal :unauthorized, result.code
  end

  # === Deactivated user ===

  test "call with deactivated user's API token returns failure" do
    @user.update!(active: false)

    result = AuthenticatesApiRequest.call(bearer: @plain_token)

    assert result.failure?
    # Service falls through to Doorkeeper (which won't match), then
    # returns the final :unauthorized. Preserves pre-refactor behavior.
    assert_equal :unauthorized, result.code
  end

  test "call with deactivated user's API token does NOT touch last_used_at" do
    @user.update!(active: false)
    assert_nil @api_token.last_used_at

    AuthenticatesApiRequest.call(bearer: @plain_token)
    @api_token.reload
    assert_nil @api_token.last_used_at
  end

  test "call with deactivated user's API token logs api_token_deactivated_user" do
    @user.update!(active: false)

    logs = capture_logs do
      AuthenticatesApiRequest.call(bearer: @plain_token)
    end

    assert_match(/event=api_token_deactivated_user/, logs)
    assert_match(/user_id=#{@user.id}/, logs)
  end

  test "call with deactivated user's Doorkeeper token returns failure" do
    doorkeeper_token = create_doorkeeper_token(uid: "oauth_deactivated")
    @user.update!(active: false)

    result = AuthenticatesApiRequest.call(bearer: doorkeeper_token.token)

    assert result.failure?
    # Service falls through to the final :unauthorized. Preserves
    # pre-refactor behavior.
    assert_equal :unauthorized, result.code
  end

  test "call with deactivated user's Doorkeeper token logs oauth_token_deactivated_user" do
    doorkeeper_token = create_doorkeeper_token(uid: "oauth_deactivated_log")
    @user.update!(active: false)

    logs = capture_logs do
      AuthenticatesApiRequest.call(bearer: doorkeeper_token.token)
    end

    assert_match(/event=oauth_token_deactivated_user/, logs)
    assert_match(/user_id=#{@user.id}/, logs)
  end

  # === Doorkeeper revoked / expired ===

  test "call with revoked Doorkeeper token returns failure" do
    doorkeeper_token = create_doorkeeper_token(uid: "oauth_revoked")
    doorkeeper_token.revoke

    result = AuthenticatesApiRequest.call(bearer: doorkeeper_token.token)

    assert result.failure?
    assert_equal :unauthorized, result.code
  end

  test "call with expired Doorkeeper token returns failure" do
    app = Doorkeeper::Application.create!(
      name: "Test OAuth App",
      uid: "oauth_expired",
      redirect_uri: "https://example.com/callback",
      scopes: "podread",
      confidential: true
    )
    doorkeeper_token = Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 0,
      created_at: 2.hours.ago
    )

    result = AuthenticatesApiRequest.call(bearer: doorkeeper_token.token)

    assert result.failure?
    assert_equal :unauthorized, result.code
  end

  # === API token preferred over Doorkeeper ===

  test "call prefers API token path when token matches API token" do
    # Happy path API token — service must take the API token branch
    # (and update last_used_at) rather than fall through to Doorkeeper.
    AuthenticatesApiRequest.call(bearer: @plain_token)

    @api_token.reload
    assert_not_nil @api_token.last_used_at
  end

  private

  def create_doorkeeper_token(uid:)
    app = Doorkeeper::Application.create!(
      name: "Test OAuth App",
      uid: uid,
      redirect_uri: "https://example.com/callback",
      scopes: "podread",
      confidential: true
    )
    Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )
  end

  def capture_logs
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(output)
    yield
    output.string
  ensure
    Rails.logger = original_logger
  end
end
