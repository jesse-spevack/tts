require "test_helper"

class Admin::ProcessingTimesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin_user)
    @regular_user = users(:one)
  end

  test "redirects unauthenticated users to root" do
    get admin_processing_times_url
    assert_redirected_to root_url
  end

  test "returns not found for non-admin users" do
    sign_in_as @regular_user

    get admin_processing_times_url
    assert_response :not_found
  end

  test "allows admin users to view processing times" do
    sign_in_as @admin

    get admin_processing_times_url
    assert_response :success
  end

  test "renders empty state when no episodes have processing data" do
    sign_in_as @admin

    get admin_processing_times_url
    assert_response :success
    assert_select "p", text: /No completed episodes with processing data yet/
  end

  test "renders empty state when no estimate model exists" do
    ProcessingEstimate.delete_all
    sign_in_as @admin

    get admin_processing_times_url
    assert_response :success
    assert_select "p", text: /No estimate model calculated yet/
    assert_select "td", text: /No estimate history yet/
  end

  test "renders scatter plot when episodes have processing data" do
    episode = episodes(:complete)
    episode.update_columns(
      processing_started_at: 2.minutes.ago,
      processing_completed_at: 1.minute.ago,
      source_text_length: 5000
    )

    sign_in_as @admin

    get admin_processing_times_url
    assert_response :success
    assert_select "svg"
    assert_select "circle"
  end

  test "renders current estimate model" do
    ProcessingEstimate.create!(
      base_seconds: 30,
      microseconds_per_character: 150,
      episode_count: 25
    )

    sign_in_as @admin

    get admin_processing_times_url
    assert_response :success
    assert_select "td", text: "30"
    assert_select "td", text: "150"
    assert_select "td", text: "25"
  end

  test "renders estimate history table" do
    3.times do |i|
      ProcessingEstimate.create!(
        base_seconds: 30 + i,
        microseconds_per_character: 150 + i * 10,
        episode_count: 20 + i * 5
      )
    end

    sign_in_as @admin

    get admin_processing_times_url
    assert_response :success
    # Should show all 3 estimates in the history table
    assert_select "tbody tr", minimum: 3
  end
end
