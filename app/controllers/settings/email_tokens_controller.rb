# frozen_string_literal: true

module Settings
  class EmailTokensController < ApplicationController
    before_action :require_authentication

    def create
      RegeneratesEmailIngestToken.call(user: Current.user)
      redirect_to settings_path, notice: "Email address regenerated."
    end
  end
end
