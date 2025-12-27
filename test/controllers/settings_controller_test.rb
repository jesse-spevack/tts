# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(tier: :free)
    sign_in_as(@user)
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"
  end

  test "show renders settings page" do
    get settings_path

    assert_response :success
    assert_select "h1", "Settings"
  end

  test "show displays available voices for free tier" do
    get settings_path

    assert_response :success
    assert_select "input[name='voice'][value='wren']"
    assert_select "input[name='voice'][value='felix']"
    assert_select "input[name='voice'][value='sloane']"
    assert_select "input[name='voice'][value='archer']"
    assert_select "input[name='voice'][value='elara']", count: 0
  end

  test "show displays all voices for unlimited tier" do
    @user.update!(tier: :unlimited)
    get settings_path

    assert_response :success
    assert_select "input[name='voice'][value='wren']"
    assert_select "input[name='voice'][value='elara']"
  end

  test "show marks current voice_preference as selected" do
    @user.update!(voice_preference: "sloane")
    get settings_path

    assert_select "input[name='voice'][value='sloane'][checked]"
  end

  test "update saves valid voice_preference" do
    patch settings_path, params: { voice: "felix" }

    assert_redirected_to settings_path
    assert_equal "Settings saved.", flash[:notice]
    assert_equal "felix", @user.reload.voice_preference
  end

  test "update rejects invalid voice" do
    patch settings_path, params: { voice: "invalid" }

    assert_redirected_to settings_path
    assert_equal "Invalid voice selection.", flash[:alert]
  end

  test "update rejects chirp voice for free tier" do
    patch settings_path, params: { voice: "elara" }

    assert_redirected_to settings_path
    assert_equal "Invalid voice selection.", flash[:alert]
  end

  test "update allows chirp voice for unlimited tier" do
    @user.update!(tier: :unlimited)
    patch settings_path, params: { voice: "elara" }

    assert_redirected_to settings_path
    assert_equal "Settings saved.", flash[:notice]
    assert_equal "elara", @user.reload.voice_preference
  end

  test "requires authentication" do
    sign_out
    get settings_path

    assert_redirected_to root_path
  end
end
