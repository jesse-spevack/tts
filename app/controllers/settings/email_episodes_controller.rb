# frozen_string_literal: true

module Settings
  class EmailEpisodesController < ApplicationController
    before_action :require_authentication

    def create
      Current.user.enable_email_episodes!
      redirect_to settings_path, notice: "Email episodes enabled."
    end

    def destroy
      Current.user.disable_email_episodes!
      redirect_to settings_path, notice: "Email episodes disabled."
    end
  end
end
