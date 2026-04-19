# frozen_string_literal: true

# Welcome-back page a soft-deleted user lands on after clicking their magic
# link. Confirming restores the account (clears deleted_at); declining signs
# them out.
class RestoreAccountsController < ApplicationController
  # Must be able to reach this controller while soft-deleted — otherwise the
  # revive flow is unreachable.
  allow_soft_deleted_access

  # The default application layout renders shared/header, which calls
  # Current.user.free? — Current.user is nil for a soft-deleted user, so use
  # the marketing layout (no auth-aware header).
  layout "marketing"

  helper_method :soft_deleted_current_user

  def new
    # If the caller is authenticated but NOT soft-deleted, there's nothing to
    # restore — bounce them into the app.
    redirect_to new_episode_path unless soft_deleted_current_user
  end

  def create
    user = session_user

    # Idempotent — if the user was already restored between loading the form
    # and submitting, just proceed.
    user.restore! if user&.soft_deleted?

    redirect_to new_episode_path,
      notice: "Welcome back. Your previous subscription was cancelled — you can resubscribe from Billing."
  end

  private

  # Current.user is nil for soft-deleted users (belongs_to :user respects
  # User.default_scope). Look them up unscoped for the revive flow.
  def session_user
    return nil unless Current.session

    @session_user ||= User.unscoped.find_by(id: Current.session.user_id)
  end

  def soft_deleted_current_user
    user = session_user
    user&.soft_deleted? ? user : nil
  end
end
