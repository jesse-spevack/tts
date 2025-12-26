class UserMailer < ApplicationMailer
  def first_episode_ready(episode:)
    @episode = episode
    @user = episode.user
    @feed_url = episode.podcast.feed_url
    @help_url = help_add_rss_feed_url

    mail(
      to: @user.email_address,
      subject: "Your first episode is ready 🎧"
    )
  end
end
