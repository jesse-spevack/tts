# frozen_string_literal: true

require "test_helper"

class EnablesEmailEpisodesTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "enables email_episodes_enabled" do
    refute @user.email_episodes_enabled?

    EnablesEmailEpisodes.call(user: @user)

    assert @user.reload.email_episodes_enabled?
  end

  test "generates email_ingest_token" do
    assert_nil @user.email_ingest_token

    EnablesEmailEpisodes.call(user: @user)

    assert_not_nil @user.reload.email_ingest_token
  end

  test "token is lowercase urlsafe base64" do
    EnablesEmailEpisodes.call(user: @user)

    token = @user.reload.email_ingest_token
    assert_equal token, token.downcase
    assert_match(/\A[a-z0-9_-]+\z/, token)
  end

  test "token is 22 characters" do
    EnablesEmailEpisodes.call(user: @user)

    assert_equal 22, @user.reload.email_ingest_token.length
  end
end
