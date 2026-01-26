# frozen_string_literal: true

require "test_helper"

module Settings
  class EmailTokensControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:one)
      EnablesEmailEpisodes.call(user: @user)
      sign_in_as(@user)
    end

    test "create regenerates email token" do
      old_token = @user.email_ingest_token

      post settings_email_token_path

      assert_redirected_to settings_path
      assert_equal "Email address regenerated.", flash[:notice]
      assert_not_equal old_token, @user.reload.email_ingest_token
    end

    test "create requires authentication" do
      sign_out

      post settings_email_token_path

      assert_redirected_to root_path
    end
  end
end
