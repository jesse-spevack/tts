require "test_helper"

class RecordSentMessageTest < ActiveSupport::TestCase
  test "creates a sent message and returns true" do
    user = users(:one)

    assert_difference "SentMessage.count", 1 do
      result = RecordSentMessage.call(user:, message_type: "first_episode_ready")
      assert result
    end
  end

  test "returns false if message already sent" do
    user = users(:one)
    SentMessage.create!(user:, message_type: "first_episode_ready")

    assert_no_difference "SentMessage.count" do
      result = RecordSentMessage.call(user:, message_type: "first_episode_ready")
      refute result
    end
  end

  test "different users can have same message type" do
    assert RecordSentMessage.call(user: users(:one), message_type: "first_episode_ready")
    assert RecordSentMessage.call(user: users(:two), message_type: "first_episode_ready")
    assert_equal 2, SentMessage.where(message_type: "first_episode_ready").count
  end

  test "same user can have different message types" do
    user = users(:one)
    assert RecordSentMessage.call(user:, message_type: "first_episode_ready")
    assert RecordSentMessage.call(user:, message_type: "welcome")
    assert_equal 2, SentMessage.where(user:).count
  end

  test "handles concurrent creation attempts gracefully" do
    user = users(:one)
    threads = 5.times.map do
      Thread.new { RecordSentMessage.call(user:, message_type: "first_episode_ready") }
    end
    results = threads.map(&:value)

    assert_equal 1, results.count(true)
    assert_equal 1, SentMessage.where(user:, message_type: "first_episode_ready").count
  end
end
