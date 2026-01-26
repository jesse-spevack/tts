# frozen_string_literal: true

module Settings
  class EmailEpisodesController < ApplicationController
    before_action :require_authentication

    def create
      EnablesEmailEpisodes.call(user: Current.user)
      redirect_to settings_path, notice: "Email episodes enabled."
    end

    def destroy
      DisablesEmailEpisodes.call(user: Current.user)
      redirect_to settings_path, notice: "Email episodes disabled."
    end
  end
end
