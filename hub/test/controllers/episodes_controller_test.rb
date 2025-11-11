require "test_helper"

class EpisodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "should get index" do
    get episodes_url
    assert_response :success
  end

  test "should get new" do
    get new_episode_url
    assert_response :success
  end

  test "should create episode" do
    assert_difference("Episode.count") do
      post episodes_url, params: { episode: { title: "Test Episode", author: "Test Author", description: "Test Description" } }
    end

    assert_redirected_to episodes_path
  end
end
