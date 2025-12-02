require "test_helper"

class EpisodeCompletionNotifierTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  test "sends first_episode_ready email for user's first completed episode" do
    episode = episodes(:one)
    episode.update!(status: :complete)

    assert_emails 1 do
      EpisodeCompletionNotifier.call(episode: episode)
    end
  end

  test "does not send email if already sent" do
    episode = episodes(:one)
    episode.update!(status: :complete)
    SentMessage.record!(user: episode.user, message_type: "first_episode_ready")

    assert_no_emails do
      EpisodeCompletionNotifier.call(episode: episode)
    end
  end

  test "records sent message after sending email" do
    episode = episodes(:one)
    episode.update!(status: :complete)

    EpisodeCompletionNotifier.call(episode: episode)

    assert SentMessage.sent?(user: episode.user, message_type: "first_episode_ready")
  end

  test "does not send email for non-complete episodes" do
    episode = episodes(:one)
    episode.update!(status: :processing)

    assert_no_emails do
      EpisodeCompletionNotifier.call(episode: episode)
    end
  end
end
