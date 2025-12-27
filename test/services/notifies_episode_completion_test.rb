# frozen_string_literal: true

require "test_helper"

class NotifiesEpisodeCompletionTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "sends first_episode_ready email for user's first completed episode" do
    episode = episodes(:one)
    episode.update!(status: :complete)

    assert_emails 1 do
      NotifiesEpisodeCompletion.call(episode:)
    end
  end

  test "does not send email if already sent" do
    episode = episodes(:one)
    episode.update!(status: :complete)
    SentMessage.create!(user: episode.user, message_type: "first_episode_ready")

    assert_no_emails do
      NotifiesEpisodeCompletion.call(episode:)
    end
  end

  test "records sent message after sending email" do
    episode = episodes(:one)
    episode.update!(status: :complete)

    NotifiesEpisodeCompletion.call(episode:)

    assert SentMessage.exists?(user: episode.user, message_type: "first_episode_ready")
  end

  test "does not send email for non-complete episodes" do
    episode = episodes(:one)
    episode.update!(status: :processing)

    assert_no_emails do
      NotifiesEpisodeCompletion.call(episode:)
    end
  end
end
