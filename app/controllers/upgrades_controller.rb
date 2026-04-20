class UpgradesController < ApplicationController
  before_action :require_authentication

  def show
    redirect_to billing_path
  end
end
