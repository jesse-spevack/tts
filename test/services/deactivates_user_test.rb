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

  test "zeros credit_balance.balance for user with positive balance" do
    user = users(:credit_user)
    balance = credit_balances(:with_credits)
    assert_equal 3, balance.balance, "fixture precondition"

    DeactivatesUser.call(user: user)

    assert_equal 0, balance.reload.balance
  end

  test "creates a single forfeit CreditTransaction for user with positive balance" do
    user = users(:credit_user)
    prior_balance = credit_balances(:with_credits).balance
    assert_equal 3, prior_balance, "fixture precondition"

    assert_difference -> { CreditTransaction.where(user: user, transaction_type: "forfeit").count }, 1 do
      DeactivatesUser.call(user: user)
    end

    forfeit = CreditTransaction.where(user: user, transaction_type: "forfeit").last
    assert_equal(-prior_balance, forfeit.amount)
    assert_equal 0, forfeit.balance_after
    assert_equal "forfeit", forfeit.transaction_type
  end

  test "succeeds and creates no forfeit transaction when user has no credit_balance" do
    user = users(:free_user)
    assert_nil user.credit_balance, "fixture precondition: free_user has no credit_balance"

    assert_no_difference -> { CreditTransaction.where(transaction_type: "forfeit").count } do
      result = DeactivatesUser.call(user: user)
      assert result.success?
    end
  end

  test "creates no forfeit transaction when credit_balance is zero" do
    user = users(:jesse)
    balance = credit_balances(:empty_balance)
    assert_equal 0, balance.balance, "fixture precondition"

    assert_no_difference -> { CreditTransaction.where(transaction_type: "forfeit").count } do
      result = DeactivatesUser.call(user: user)
      assert result.success?
    end

    assert_equal 0, balance.reload.balance
  end

  test "rolls back credit forfeit when user.update! raises" do
    user = users(:credit_user)
    balance = credit_balances(:with_credits)
    prior_balance_value = balance.balance
    assert_equal 3, prior_balance_value, "fixture precondition"
    prior_forfeit_count = CreditTransaction.where(user: user, transaction_type: "forfeit").count

    def user.update!(*)
      raise ActiveRecord::RecordInvalid.new(self)
    end

    result = DeactivatesUser.call(user: user)

    assert result.failure?
    assert_equal prior_balance_value, balance.reload.balance, "balance should NOT be zeroed after rollback"
    assert_equal prior_forfeit_count,
      CreditTransaction.where(user: user, transaction_type: "forfeit").count,
      "no forfeit transaction should be persisted after rollback"
  end

  # agent-team-h60: DeleteEpisodeJob must be gated on transaction commit so
  # the user is not left in a still-active state while delete jobs fire.
  test "enqueues no DeleteEpisodeJob when user.update! raises" do
    podcast = podcasts(:one)
    2.times do |i|
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

    def @user.update!(*)
      raise ActiveRecord::RecordInvalid.new(self)
    end

    assert_no_enqueued_jobs only: DeleteEpisodeJob do
      DeactivatesUser.call(user: @user)
    end
  end

  # agent-team-k15: persist a durable audit row inside the same transaction.
  test "creates a Deactivation audit row inside the transaction" do
    freeze_time do
      assert_difference -> { Deactivation.where(user: @user).count }, 1 do
        DeactivatesUser.call(user: @user)
      end

      record = Deactivation.where(user: @user).last
      assert_equal Time.current, record.deactivated_at
    end
  end

  test "does not create a Deactivation audit row when update! raises" do
    def @user.update!(*)
      raise ActiveRecord::RecordInvalid.new(self)
    end

    assert_no_difference -> { Deactivation.where(user: @user).count } do
      DeactivatesUser.call(user: @user)
    end
  end

  test "leaves user.active unchanged when update! raises" do
    assert @user.active, "fixture precondition"

    def @user.update!(*)
      raise ActiveRecord::RecordInvalid.new(self)
    end

    DeactivatesUser.call(user: @user)

    assert @user.reload.active, "user.active should remain true after rollback"
  end

  test "rolls back all cleanup steps when user.update! raises" do
    api_token = GeneratesApiToken.call(user: @user)
    session = @user.sessions.create!(ip_address: "1.2.3.4", user_agent: "test")
    app = Doorkeeper::Application.create!(
      name: "Test App",
      uid: "test_uid_#{SecureRandom.hex}",
      redirect_uri: "http://localhost/callback",
      scopes: "podread",
      confidential: false
    )
    oauth_access_token = Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )
    oauth_access_grant = Doorkeeper::AccessGrant.create!(
      application: app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 10.minutes,
      redirect_uri: "http://localhost/callback"
    )

    original_email = @user.email_address
    original_active = @user.active
    original_session_count = @user.sessions.count

    def @user.update!(*)
      raise ActiveRecord::RecordInvalid.new(self)
    end

    result = DeactivatesUser.call(user: @user)

    assert result.failure?
    assert_nil api_token.reload.revoked_at, "api_token should NOT be revoked after rollback"
    assert_equal original_session_count, @user.sessions.count, "sessions should be intact after rollback"
    assert @user.sessions.exists?(id: session.id), "original session should still exist"
    assert_nil oauth_access_token.reload.revoked_at, "oauth_access_token should NOT be revoked after rollback"
    assert_nil oauth_access_grant.reload.revoked_at, "oauth_access_grant should NOT be revoked after rollback"

    @user.reload
    assert_equal original_active, @user.active, "active flag should be unchanged after rollback"
    assert_equal original_email, @user.email_address, "email_address should be unchanged after rollback"
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
