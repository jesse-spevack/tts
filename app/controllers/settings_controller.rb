# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :require_authentication

  def show
    @voices = Current.user.available_voices.map do |key|
      Voice.find(key).merge(key: key, sample_url: Voice.sample_url(key))
    end
    @selected_voice = Current.user.voice_preference
    @email_ingest_address = Current.user.email_ingest_address
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
