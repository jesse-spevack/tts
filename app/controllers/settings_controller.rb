# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :require_authentication

  def show
    @voices = Current.user.available_voices.map do |key|
      Voice.find(key).merge(key: key, sample_url: Voice.sample_url(key))
    end
    @selected_voice = Current.user.voice_preference
  end

  def update
    voice = params[:voice]

    if voice.present? && !Current.user.available_voices.include?(voice)
      redirect_to settings_path, alert: "Invalid voice selection."
      return
    end

    update_params = {}
    update_params[:voice_preference] = voice if voice.present?

    if params.key?(:email_episode_confirmation)
      update_params[:email_episode_confirmation] = params[:email_episode_confirmation] == "1"
    end

    if Current.user.update(update_params)
      redirect_to settings_path, notice: "Settings saved."
    else
      redirect_to settings_path, alert: "Failed to update settings."
    end
  end
end
