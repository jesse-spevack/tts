# frozen_string_literal: true

# Soft-deletes a user and revokes every auth artifact tied to the account.
# Sessions are destroyed outright; API tokens and Doorkeeper access tokens
# get revoked_at stamped. Stripe cancellation is enqueued best-effort so the
# local soft-delete commits immediately and honors user intent.
class SoftDeletesUser
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    raise "User already deleted" if user.soft_deleted?

    User.transaction do
      user.update!(deleted_at: Time.current)

      # Defense in depth: revoke every auth artifact at the source instead of
      # relying on per-path soft-delete checks.
      # update_all skips per-record callbacks intentionally — revocation is a
      # pure timestamp write and we don't want ActiveRecord to instantiate
      # every token just to stamp revoked_at.
      user.api_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
      user.sessions.destroy_all
      user.oauth_access_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
    end

    # Stripe cancellation retries on its own if the API is unavailable. If
    # there's no active subscription the job logs + returns early.
    CancelsUserSubscriptionJob.perform_later(user_id: user.id)
  end

  private

  attr_reader :user
end
