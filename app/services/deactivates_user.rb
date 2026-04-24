# frozen_string_literal: true

# Anonymize-in-place account deactivation. Rotates the user's identifiable
# data to a sentinel value, flips active=false, and enqueues blob/Stripe
# cleanup so the synchronous path commits immediately.
#
# Order matters:
#   1. Sessions destroyed (forces logout everywhere)
#   2. API tokens revoked (revoked_at set, not deleted — preserves audit trail)
#   3. OAuth access tokens + grants revoked (Doorkeeper flips revoked_at)
#   4. Credit balance forfeited (transaction recorded; balance zeroed)
#   5. Email rotated, auth/ingest tokens nulled, active=false (the thing
#      that makes future auth fail)
#   6. (Post-commit) Episode blob cleanup + Stripe subscription cancellation
#      enqueued as background jobs.
#
# Email rotation happens LAST inside the transaction because once the
# unique-constrained email_address is mutated, a re-signup with the original
# address succeeds naturally — that path must not race against any of the
# cleanup above.
#
# Background jobs (DeleteEpisodeJob, CancelsUserSubscriptionJob) are
# enqueued ONLY after the transaction commits (agent-team-h60). Enqueuing
# them inside the transaction would let them fire — and destroy blobs or
# cancel Stripe — even if the deactivation rolled back, leaving the user
# still active but with data missing.
class DeactivatesUser
  include StructuredLogging

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    episode_ids = @user.episodes.pluck(:id)

    ActiveRecord::Base.transaction do
      @user.sessions.destroy_all
      @user.api_tokens.update_all(revoked_at: Time.current)
      @user.oauth_access_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
      @user.oauth_access_grants.where(revoked_at: nil).update_all(revoked_at: Time.current)
      if (balance = @user.credit_balance) && balance.balance.positive?
        CreditTransaction.create!(
          user: @user,
          amount: -balance.balance,
          balance_after: 0,
          transaction_type: "forfeit"
        )
        balance.update!(balance: 0)
      end
      # agent-team-k15: durable audit row. Same transaction as the user
      # update, so a rollback also rolls back the audit — support/finance
      # should never see a Deactivation row for a still-active user.
      Deactivation.create!(user: @user, deactivated_at: Time.current)
      @user.update!(
        email_address: "deleted-#{@user.id}@deleted.invalid",
        active: false,
        auth_token: nil,
        auth_token_expires_at: nil,
        email_ingest_token: nil
      )
    end

    episode_ids.each { |id| DeleteEpisodeJob.perform_later(episode_id: id) }
    CancelsUserSubscriptionJob.perform_later(user_id: @user.id)

    log_info "user_deactivated", user_id: @user.id, episode_count: episode_ids.size
    Result.success(user: @user)
  rescue => e
    log_error "deactivates_user_failed",
      user_id: @user.id,
      error_class: e.class.name,
      error: e.message
    Result.failure(e.message)
  end
end
