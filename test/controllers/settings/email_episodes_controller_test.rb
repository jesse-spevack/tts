# frozen_string_literal: true

require "test_helper"

module Settings
  class EmailEpisodesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      sign_in_as(@user)
    end

    test "create enables email episodes for user" do
      refute @user.email_episodes_enabled?

      post settings_email_episodes_path

      assert_redirected_to settings_path
      assert_equal "Email episodes enabled.", flash[:notice]
      assert @user.reload.email_episodes_enabled?
      assert_not_nil @user.email_ingest_token
    end

    test "destroy disables email episodes for user" do
      EnablesEmailEpisodes.call(user: @user)

      delete settings_email_episodes_path

      assert_redirected_to settings_path
      assert_equal "Email episodes disabled.", flash[:notice]
      refute @user.reload.email_episodes_enabled?
      assert_nil @user.email_ingest_token
    end

    test "create requires authentication" do
      sign_out

      post settings_email_episodes_path

      assert_redirected_to root_path
    end

    test "destroy requires authentication" do
      sign_out

      delete settings_email_episodes_path

      assert_redirected_to root_path
    end
  end
end
