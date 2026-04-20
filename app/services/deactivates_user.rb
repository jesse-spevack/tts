# frozen_string_literal: true

# Anonymize-in-place account deactivation. Rotates the user's identifiable
# data to a sentinel value, flips active=false, and enqueues blob/Stripe
# cleanup so the synchronous path commits immediately.
#
# Order matters:
#   1. Episode blob cleanup (async via DeleteEpisodeJob)
#   2. Sessions destroyed (forces logout everywhere)
#   3. API tokens revoked (revoked_at set, not deleted — preserves audit trail)
#   4. OAuth access tokens + grants revoked (Doorkeeper flips revoked_at)
#   5. Stripe subscription canceled (async, retries on its own)
#   6. Email rotated, auth/ingest tokens nulled, active=false (the thing that makes future auth fail)
#
# Email rotation happens LAST because once the unique-constrained
# email_address is mutated, a re-signup with the original address succeeds
# naturally — that path must not race against any of the cleanup above.
class DeactivatesUser
  include StructuredLogging

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    episode_count = @user.episodes.size

    @user.episodes.find_each do |episode|
      DeleteEpisodeJob.perform_later(episode_id: episode.id)
    end
    @user.sessions.destroy_all
    @user.api_tokens.update_all(revoked_at: Time.current)
    @user.oauth_access_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
    @user.oauth_access_grants.where(revoked_at: nil).update_all(revoked_at: Time.current)
    CancelsUserSubscriptionJob.perform_later(user_id: @user.id)
    @user.update!(
      email_address: "deleted-#{@user.id}@deleted.invalid",
      active: false,
      auth_token: nil,
      auth_token_expires_at: nil,
      email_ingest_token: nil
    )

    log_info "user_deactivated", user_id: @user.id, episode_count: episode_count
    Result.success(user: @user)
  rescue => e
    log_error "deactivates_user_failed",
      user_id: @user.id,
      error_class: e.class.name,
      error: e.message
    Result.failure(e.message)
  end
end
