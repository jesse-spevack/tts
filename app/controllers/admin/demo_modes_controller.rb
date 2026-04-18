module Admin
  class DemoModesController < ApplicationController
    before_action :require_admin

    def create
      session[:demo_mode] = !session[:demo_mode]
      redirect_back(fallback_location: root_path)
    end

    private

    def require_admin
      head :not_found unless Current.user_admin?
    end
  end
end
