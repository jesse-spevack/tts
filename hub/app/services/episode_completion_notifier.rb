class EpisodeCompletionNotifier
  def self.call(episode:)
    new(episode: episode).call
  end

  def initialize(episode:)
    @episode = episode
  end

  def call
    return unless episode.complete?

    send_first_episode_email if should_send_first_episode_email?
  end

  private

  attr_reader :episode

  def should_send_first_episode_email?
    !SentMessage.sent?(user: episode.user, message_type: "first_episode_ready")
  end

  def send_first_episode_email
    UserMailer.first_episode_ready(episode: episode).deliver_later
    SentMessage.record!(user: episode.user, message_type: "first_episode_ready")
  end
end
