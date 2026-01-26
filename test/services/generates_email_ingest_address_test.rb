# frozen_string_literal: true

require "test_helper"

class GeneratesEmailIngestAddressTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "returns nil when email episodes disabled" do
    refute @user.email_episodes_enabled?

    result = GeneratesEmailIngestAddress.call(user: @user)

    assert_nil result
  end

  test "returns formatted address when enabled" do
    EnablesEmailEpisodes.call(user: @user)

    result = GeneratesEmailIngestAddress.call(user: @user)

    assert_equal "readtome+#{@user.email_ingest_token}@tts.verynormal.dev", result
  end

  test "address includes user token" do
    EnablesEmailEpisodes.call(user: @user)

    result = GeneratesEmailIngestAddress.call(user: @user)

    assert_includes result, @user.email_ingest_token
  end

  test "address matches expected format" do
    EnablesEmailEpisodes.call(user: @user)

    result = GeneratesEmailIngestAddress.call(user: @user)

    assert_match(/\Areadtome\+[a-z0-9_-]+@tts\.verynormal\.dev\z/, result)
  end
end
