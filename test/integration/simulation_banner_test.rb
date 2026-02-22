# frozen_string_literal: true

require "test_helper"

class SimulationBannerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "simulation banner is not rendered when simulation mode is off" do
    Rails.application.config.simulation_mode = false

    get episodes_url

    assert_response :success
    assert_no_match(/Simulation Mode/, response.body)
  end

  test "simulation banner is rendered when simulation mode is on" do
    Rails.application.config.simulation_mode = true

    begin
      get episodes_url

      assert_response :success
      assert_match(/Simulation Mode/, response.body)
    ensure
      Rails.application.config.simulation_mode = false
    end
  end
end
