# frozen_string_literal: true

require "test_helper"

class RegeneratesEmailIngestTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    EnablesEmailEpisodes.call(user: @user)
    @old_token = @user.email_ingest_token
  end

  test "generates a new token" do
    RegeneratesEmailIngestToken.call(user: @user)

    assert_not_equal @old_token, @user.reload.email_ingest_token
  end

  test "new token is lowercase urlsafe base64" do
    RegeneratesEmailIngestToken.call(user: @user)

    token = @user.reload.email_ingest_token
    assert_equal token, token.downcase
    assert_match(/\A[a-z0-9_-]+\z/, token)
  end

  test "new token is 22 characters" do
    RegeneratesEmailIngestToken.call(user: @user)

    assert_equal 22, @user.reload.email_ingest_token.length
  end
end
