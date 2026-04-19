# frozen_string_literal: true

module Settings
  class AccountsController < ApplicationController
    # Thin proxy around Rails.cache so the rate_limit store is resolved at
    # request time. Rails 8 `rate_limit` captures its `store:` at class-load
    # via the `cache_store` default, and the test env default is :null_store
    # (no-op). Without this indirection, the AccountsControllerTest can't
    # swap Rails.cache to a MemoryStore to exercise the limiter.
    class RateLimitStore
      def increment(*args, **kwargs) = Rails.cache.increment(*args, **kwargs)
    end

    before_action :require_authentication

    # Rails 8 built-in rate_limit — 1 deletion attempt per hour per user.
    # Key is prefixed so two users never collide, and the nil-user guard in
    # `by:` prevents a single shared key if the session is missing.
    rate_limit to: 1,
               within: 1.hour,
               by: -> { "user:#{Current.user&.id}" },
               store: RateLimitStore.new,
               with: -> {
                 redirect_to root_path,
                   alert: "Your account has been deleted. If you didn't intend this, contact support."
               },
               only: :destroy

    def destroy
      Current.user.soft_delete!
      terminate_session
      redirect_to root_path, status: :see_other, notice: "Your account has been deleted."
    end
  end
end
