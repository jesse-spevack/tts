# frozen_string_literal: true

module Settings
  class AccountsController < ApplicationController
    # Rails 8 built-in rate_limit — 1 deletion attempt per hour per user.
    # Key is prefixed so two users never collide, and the nil-user guard in
    # `by:` prevents a single shared key if the session is missing.
    rate_limit to: 1,
               within: 1.hour,
               by: -> { "user:#{Current.user&.id}" },
               store: CacheStoreRateLimitProxy.new,
               with: -> {
                 redirect_to root_path,
                   alert: "Your account has been deleted. If you didn't intend this, contact support."
               },
               only: :destroy

    def destroy
      SoftDeletesUser.call(user: Current.user)
      terminate_session
      redirect_to root_path, status: :see_other, notice: "Your account has been deleted."
    end
  end
end
