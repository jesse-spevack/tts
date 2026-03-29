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

      # Revoke all access tokens and grants for this user + app
      Doorkeeper::AccessToken
        .where(resource_owner_id: Current.user.id, application_id: app.id)
        .update_all(revoked_at: Time.current)

      Doorkeeper::AccessGrant
        .where(resource_owner_id: Current.user.id, application_id: app.id)
        .update_all(revoked_at: Time.current)

      redirect_to settings_path, notice: "#{app.name} has been disconnected."
    end
  end
end
