# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :require_authentication

  def show
    @voices = Current.user.available_voices.map { |key| Voice.find(key) }
    @selected_voice = Current.user.voice_preference
    @email_ingest_address = Current.user.email_ingest_address
    @connected_apps = connected_oauth_apps
  end

  def update
    voice = settings_params[:voice_preference]

    if voice.present? && !Current.user.available_voices.include?(voice)
      redirect_to settings_path, alert: "Invalid voice selection."
      return
    end

    if Current.user.update(settings_params)
      redirect_to settings_path, notice: "Settings saved."
    else
      redirect_to settings_path, alert: "Failed to update settings."
    end
  end

  private

  def connected_oauth_apps
    # Find OAuth apps with non-revoked tokens for this user.
    # Filter expired tokens in Ruby since SQLite datetime arithmetic is non-standard.
    tokens = Doorkeeper::AccessToken
      .where(resource_owner_id: Current.user.id)
      .where(revoked_at: nil)
      .includes(:application)
      .order(created_at: :desc)

    # Group by app, keep only apps with at least one non-expired token
    tokens
      .select { |t| !t.expired? }
      .group_by(&:application)
      .map do |app, app_tokens|
        {
          app: app,
          authorized_at: app_tokens.first&.created_at
        }
      end
  end

  def settings_params
    permitted = params.permit(:voice, :email_episode_confirmation)

    result = {}
    result[:voice_preference] = permitted[:voice] if permitted[:voice].present?

    if permitted.key?(:email_episode_confirmation)
      result[:email_episode_confirmation] = permitted[:email_episode_confirmation] == "1"
    end

    result
  end
end
