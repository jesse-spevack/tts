# frozen_string_literal: true

module Settings
  class ConnectedAppsController < ApplicationController
    before_action :require_authentication

    def destroy
      app = Doorkeeper::Application.find_by(id: params[:id])

      unless app
        redirect_to settings_path, alert: "App not found."
        return
      end

      DisconnectsOauthApplication.call(user: Current.user, application: app)

      redirect_to settings_path, notice: "#{app.name} has been disconnected."
    end
  end
end
