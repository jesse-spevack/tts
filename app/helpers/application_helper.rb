module ApplicationHelper
  def simulation_mode?
    Rails.application.config.simulation_mode
  end

  def demo_mode?
    session[:demo_mode] == true
  end
end
