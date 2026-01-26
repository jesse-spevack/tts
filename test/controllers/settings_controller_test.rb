# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(account_type: :standard)
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
    @user.update!(account_type: :unlimited)
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
    @user.update!(account_type: :unlimited)
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

  # Email episodes tests
  test "enable_email_episodes enables email episodes for user" do
    refute @user.email_episodes_enabled?

    post enable_email_episodes_settings_path

    assert_redirected_to settings_path
    assert_equal "Email episodes enabled.", flash[:notice]
    assert @user.reload.email_episodes_enabled?
    assert_not_nil @user.email_ingest_token
  end

  test "disable_email_episodes disables email episodes for user" do
    @user.enable_email_episodes!

    post disable_email_episodes_settings_path

    assert_redirected_to settings_path
    assert_equal "Email episodes disabled.", flash[:notice]
    refute @user.reload.email_episodes_enabled?
    assert_nil @user.email_ingest_token
  end

  test "regenerate_email_token generates new token" do
    @user.enable_email_episodes!
    old_token = @user.email_ingest_token

    post regenerate_email_token_settings_path

    assert_redirected_to settings_path
    assert_equal "Email address regenerated.", flash[:notice]
    assert_not_equal old_token, @user.reload.email_ingest_token
  end

  test "show displays email episodes section when disabled" do
    get settings_path

    assert_response :success
    assert_select "h2", text: "Email to Podcast"
    assert_select "button", text: "Enable Email Episodes"
  end

  test "show displays email ingest address when enabled" do
    @user.enable_email_episodes!

    get settings_path

    assert_response :success
    assert_select "code", text: @user.email_ingest_address
    assert_select "button", text: "Disable"
    assert_select "button", text: "Regenerate Address"
  end

  test "update saves email_episode_confirmation preference" do
    @user.update!(email_episode_confirmation: true)

    patch settings_path, params: { email_episode_confirmation: "0" }

    assert_redirected_to settings_path
    refute @user.reload.email_episode_confirmation?
  end

  test "update enables email_episode_confirmation" do
    @user.update!(email_episode_confirmation: false)

    patch settings_path, params: { email_episode_confirmation: "1" }

    assert_redirected_to settings_path
    assert @user.reload.email_episode_confirmation?
  end
end
