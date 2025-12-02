require "test_helper"

class SentMessageTest < ActiveSupport::TestCase
  test "requires user" do
    message = SentMessage.new(message_type: "first_episode_ready")
    refute message.valid?
    assert_includes message.errors[:user], "must exist"
  end

  test "requires message_type" do
    message = SentMessage.new(user: users(:one))
    refute message.valid?
    assert_includes message.errors[:message_type], "can't be blank"
  end

  test "enforces uniqueness of message_type per user" do
    SentMessage.create!(user: users(:one), message_type: "first_episode_ready")
    duplicate = SentMessage.new(user: users(:one), message_type: "first_episode_ready")
    refute duplicate.valid?
    assert_includes duplicate.errors[:message_type], "has already been taken"
  end

  test "allows same message_type for different users" do
    SentMessage.create!(user: users(:one), message_type: "first_episode_ready")
    other = SentMessage.new(user: users(:two), message_type: "first_episode_ready")
    assert other.valid?
  end
end
