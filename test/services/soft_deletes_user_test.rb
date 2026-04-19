require "test_helper"

class SoftDeletesUserTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "sets deleted_at and enqueues Stripe cancel job" do
    user = users(:one)

    assert_enqueued_with(job: CancelsUserSubscriptionJob, args: [ { user_id: user.id } ]) do
      SoftDeletesUser.call(user: user)
    end

    assert user.soft_deleted?
    assert_not_nil user.deleted_at
  end

  test "raises if the user is already deleted" do
    user = users(:one)
    user.update!(deleted_at: Time.current)

    assert_raises(RuntimeError) { SoftDeletesUser.call(user: user) }
  end

  # Defense-in-depth: every auth artifact must be revoked at the source on
  # soft-delete, not just denied at the lookup layer.
  test "revokes the user's API tokens" do
    user = users(:one)
    token = user.api_tokens.create!(token_digest: "soft_delete_token_digest")
    assert_nil token.revoked_at

    SoftDeletesUser.call(user: user)

    assert_not_nil token.reload.revoked_at
  end

  test "destroys the user's sessions" do
    user = users(:one)
    user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    assert_operator user.sessions.count, :>, 0

    SoftDeletesUser.call(user: user)

    assert_equal 0, user.sessions.reload.count
  end

  test "revokes the user's Doorkeeper access tokens" do
    user = users(:one)
    app = Doorkeeper::Application.create!(
      name: "test_app_revoke",
      uid: "soft_delete_app_uid",
      redirect_uri: "https://example.com/cb",
      scopes: "podread",
      confidential: false
    )
    token = Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: user.id,
      scopes: "podread",
      expires_in: 1.hour
    )
    assert_nil token.revoked_at

    SoftDeletesUser.call(user: user)

    assert_not_nil token.reload.revoked_at
  end
end
