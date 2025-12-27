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

    if Current.user.update(voice_preference: voice)
      redirect_to settings_path, notice: "Settings saved."
    else
      redirect_to settings_path, alert: "Invalid voice selection."
    end
  end
end
