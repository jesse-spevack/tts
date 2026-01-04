require "test_helper"

class CreatesUserTest < ActiveSupport::TestCase
  test "creates a user with the given email" do
    result = CreatesUser.call(email_address: "newuser@example.com")

    assert result.success?
    assert_not_nil result.data[:user]
    assert_equal "newuser@example.com", result.data[:user].email_address
  end

  test "creates a default podcast for the user" do
    result = CreatesUser.call(email_address: "newuser@example.com")

    assert result.success?
    assert_not_nil result.data[:podcast]
    assert_equal "newuser@example.com's Very Normal Podcast", result.data[:podcast].title
  end

  test "creates user and podcast in a transaction" do
    result = CreatesUser.call(email_address: "newuser@example.com")

    assert result.success?
    assert_equal 1, result.data[:user].podcasts.count
    assert_equal result.data[:podcast], result.data[:user].podcasts.first
  end

  test "returns failure if user creation fails" do
    result = CreatesUser.call(email_address: "invalid")

    assert_not result.success?
    assert_nil result.data
  end
end
