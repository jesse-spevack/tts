# frozen_string_literal: true

require "test_helper"

class DisablesEmailEpisodesTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    EnablesEmailEpisodes.call(user: @user)
  end

  test "disables email_episodes_enabled" do
    assert @user.email_episodes_enabled?

    DisablesEmailEpisodes.call(user: @user)

    refute @user.reload.email_episodes_enabled?
  end

  test "clears email_ingest_token" do
    assert_not_nil @user.email_ingest_token

    DisablesEmailEpisodes.call(user: @user)

    assert_nil @user.reload.email_ingest_token
  end
end
