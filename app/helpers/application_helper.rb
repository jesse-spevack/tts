module ApplicationHelper
  def simulation_mode?
    Rails.application.config.simulation_mode
  end
end
