# frozen_string_literal: true

module Settings
  class EmailTokensController < ApplicationController
    before_action :require_authentication

    def create
      Current.user.regenerate_email_ingest_token!
      redirect_to settings_path, notice: "Email address regenerated."
    end
  end
end
