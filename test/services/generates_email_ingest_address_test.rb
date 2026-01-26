# frozen_string_literal: true

require "test_helper"

class GeneratesEmailIngestAddressTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @configured_domain = Rails.configuration.x.email_ingest_domain
  end

  test "returns nil when email episodes disabled" do
    refute @user.email_episodes_enabled?

    result = GeneratesEmailIngestAddress.call(user: @user)

    assert_nil result
  end

  test "returns formatted address when enabled" do
    EnablesEmailEpisodes.call(user: @user)

    result = GeneratesEmailIngestAddress.call(user: @user)

    assert_equal "readtome+#{@user.email_ingest_token}@#{@configured_domain}", result
  end

  test "address includes user token" do
    EnablesEmailEpisodes.call(user: @user)

    result = GeneratesEmailIngestAddress.call(user: @user)

    assert_includes result, @user.email_ingest_token
  end

  test "address matches expected format" do
    EnablesEmailEpisodes.call(user: @user)

    result = GeneratesEmailIngestAddress.call(user: @user)

    escaped_domain = Regexp.escape(@configured_domain)
    assert_match(/\Areadtome\+[a-z0-9_-]+@#{escaped_domain}\z/, result)
  end

  test "uses configured email ingest domain" do
    EnablesEmailEpisodes.call(user: @user)

    result = GeneratesEmailIngestAddress.call(user: @user)

    assert result.end_with?("@#{@configured_domain}")
  end
end
