# frozen_string_literal: true

require "test_helper"

class EpisodeCostRequestTest < ActiveSupport::TestCase
  test "carries the fields needed for cost calculation" do
    user = users(:credit_user)
    req = EpisodeCostRequest.new(
      user: user,
      source_type: "text",
      text: "hello"
    )

    assert_equal user, req.user
    assert_equal "text", req.source_type
    assert_equal "hello", req.text
    assert_nil req.url
    assert_nil req.upload
    assert_nil req.source_text_length
  end

  test "coerces source_type to string" do
    req = EpisodeCostRequest.new(user: users(:credit_user), source_type: :url)
    assert_equal "url", req.source_type
  end

  test "accepts a pre-computed source_text_length" do
    req = EpisodeCostRequest.new(
      user: users(:credit_user),
      source_type: "upload",
      source_text_length: 12_345
    )
    assert_equal 12_345, req.source_text_length
  end

  test "instances are frozen" do
    req = EpisodeCostRequest.new(user: users(:credit_user), source_type: "text")
    assert_predicate req, :frozen?
  end
end
