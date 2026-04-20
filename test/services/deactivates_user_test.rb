# frozen_string_literal: true

require "test_helper"

class DeactivatesUserTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:free_user)
  end

  test "enqueues DeleteEpisodeJob per episode" do
    podcast = podcasts(:one)
    3.times do |i|
      Episode.create!(
        user: @user,
        podcast: podcast,
        title: "Episode #{i}",
        author: "Test Author",
        description: "Test description",
        source_type: :url,
        source_url: "https://example.com/#{i}",
        status: :complete
      )
    end

    assert_enqueued_jobs @user.episodes.size, only: DeleteEpisodeJob do
      DeactivatesUser.call(user: @user)
    end
  end

  test "destroys all sessions for the user" do
    @user.sessions.create!(ip_address: "1.2.3.4", user_agent: "test")
    @user.sessions.create!(ip_address: "5.6.7.8", user_agent: "test")

    assert_difference -> { @user.sessions.count }, -2 do
      DeactivatesUser.call(user: @user)
    end
  end

  test "revokes all non-revoked api_tokens" do
    token_a = GeneratesApiToken.call(user: @user)
    token_b = GeneratesApiToken.call(user: @user)

    freeze_time do
      DeactivatesUser.call(user: @user)

      assert_not_nil token_a.reload.revoked_at
      assert_not_nil token_b.reload.revoked_at
      assert_equal Time.current, token_a.revoked_at
    end
  end

  test "revokes all oauth_access_tokens and oauth_access_grants" do
    app = Doorkeeper::Application.create!(
      name: "Test App",
      uid: "test_uid_#{SecureRandom.hex}",
      redirect_uri: "http://localhost/callback",
      scopes: "podread",
      confidential: false
    )
    token = Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )
    grant = Doorkeeper::AccessGrant.create!(
      application: app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 10.minutes,
      redirect_uri: "http://localhost/callback"
    )

    DeactivatesUser.call(user: @user)

    assert token.reload.revoked?
    assert grant.reload.revoked?
  end

  test "enqueues CancelsUserSubscriptionJob exactly once" do
    assert_enqueued_with(job: CancelsUserSubscriptionJob, args: [ { user_id: @user.id } ]) do
      DeactivatesUser.call(user: @user)
    end
  end

  test "rotates email and sets active false" do
    original_id = @user.id

    DeactivatesUser.call(user: @user)

    @user.reload
    assert_equal "deleted-#{original_id}@deleted.invalid", @user.email_address
    assert_not @user.active
    assert @user.deactivated?
  end

  test "nulls auth_token, auth_token_expires_at, and email_ingest_token" do
    @user.update!(
      auth_token: "tok_#{SecureRandom.hex}",
      auth_token_expires_at: 1.hour.from_now,
      email_ingest_token: "ingest_#{SecureRandom.hex}"
    )

    DeactivatesUser.call(user: @user)

    @user.reload
    assert_nil @user.auth_token
    assert_nil @user.auth_token_expires_at
    assert_nil @user.email_ingest_token
  end

  test "logs user_deactivated structured event on success" do
    podcast = podcasts(:one)
    Episode.create!(
      user: @user,
      podcast: podcast,
      title: "Only",
      author: "Test Author",
      description: "Test description",
      source_type: :url,
      source_url: "https://example.com/only",
      status: :complete
    )

    log_output = capture_logs do
      DeactivatesUser.call(user: @user)
    end

    assert_match(/event=user_deactivated/, log_output)
    assert_match(/user_id=#{@user.id}/, log_output)
    assert_match(/episode_count=1/, log_output)
  end

  test "returns Result.success on happy path" do
    result = DeactivatesUser.call(user: @user)

    assert result.success?
    assert_equal @user, result.data[:user]
  end

  test "returns Result.failure and logs when user.update! raises" do
    # Force the final update! to fail by stubbing it.
    def @user.update!(*)
      raise ActiveRecord::RecordInvalid.new(self)
    end

    log_output = capture_logs do
      result = DeactivatesUser.call(user: @user)
      assert result.failure?
      assert_match(/Validation failed/i, result.error)
    end

    assert_match(/event=deactivates_user_failed/, log_output)
    assert_match(/user_id=#{@user.id}/, log_output)
  end

  private

  def capture_logs
    original_logger = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original_logger
  end
end
