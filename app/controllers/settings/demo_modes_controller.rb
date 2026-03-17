# frozen_string_literal: true

module Settings
  class DemoModesController < ApplicationController
    before_action :require_authentication

    def create
      return head :not_found unless Current.user_admin?

      session[:demo_mode] = !session[:demo_mode]
      redirect_to settings_path
    end
  end
end
