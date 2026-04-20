# frozen_string_literal: true

module Settings
  class AccountDeletionsController < ApplicationController
    # Forwards cache calls to whatever `Rails.cache` currently points at. Needed
    # because `rate_limit` captures the `store:` value at class-definition time,
    # but we want the live `Rails.cache` so tests can override it per-test (the
    # test env default is :null_store, which silently drops increments).
    class RailsCacheProxy
      def increment(...)
        Rails.cache.increment(...)
      end

      def decrement(...)
        Rails.cache.decrement(...)
      end
    end
    private_constant :RailsCacheProxy

    CONFIRMATION_WORD = "DELETE"

    before_action :require_authentication

    rate_limit to: 1, within: 1.hour,
               by: -> { Current.user.id.to_s },
               with: -> { redirect_to settings_path, alert: "Please try again later." },
               store: RailsCacheProxy.new,
               only: :create

    def new
    end

    def create
      unless params[:confirmation] == CONFIRMATION_WORD
        flash.now[:alert] = "Please type #{CONFIRMATION_WORD} exactly to confirm."
        return render :new, status: :unprocessable_entity
      end

      result = DeactivatesUser.call(user: Current.user)

      if result.success?
        reset_session
        redirect_to root_path, notice: "Your account has been deleted."
      else
        redirect_to settings_path, alert: "We couldn't delete your account. Please try again or contact support."
      end
    end
  end
end
