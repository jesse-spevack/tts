# frozen_string_literal: true

class NotifiesEpisodeCompletion
  def self.call(episode:)
    new(episode:).call
  end

  def initialize(episode:)
    @episode = episode
  end

  def call
    return unless episode.complete?

    send_first_episode_email
  end

  private

  attr_reader :episode

  def send_first_episode_email
    return unless RecordSentMessage.call(user: episode.user, message_type: SentMessage::FIRST_EPISODE_READY)

    UserMailer.first_episode_ready(episode:).deliver_later
  end
end
