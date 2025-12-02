require "test_helper"

class SentMessageTest < ActiveSupport::TestCase
  test "sent? returns false when no message has been sent" do
    user = users(:one)
    refute SentMessage.sent?(user: user, message_type: "first_episode_ready")
  end

  test "sent? returns true when message has been sent" do
    user = users(:one)
    SentMessage.record!(user: user, message_type: "first_episode_ready")
    assert SentMessage.sent?(user: user, message_type: "first_episode_ready")
  end

  test "record! creates a sent message" do
    user = users(:one)
    assert_difference "SentMessage.count", 1 do
      SentMessage.record!(user: user, message_type: "first_episode_ready")
    end
  end

  test "record! raises error on duplicate message type for same user" do
    user = users(:one)
    SentMessage.record!(user: user, message_type: "first_episode_ready")
    assert_raises ActiveRecord::RecordInvalid do
      SentMessage.record!(user: user, message_type: "first_episode_ready")
    end
  end

  test "different users can have same message type" do
    SentMessage.record!(user: users(:one), message_type: "first_episode_ready")
    SentMessage.record!(user: users(:two), message_type: "first_episode_ready")
    assert_equal 2, SentMessage.where(message_type: "first_episode_ready").count
  end
end
