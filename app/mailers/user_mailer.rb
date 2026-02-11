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

  def feed_url_migration(user:)
    @user = user
    @feed_url = user.primary_podcast.feed_url
    @blog_url = "https://podread.app/blog/rebrand"

    mail(
      to: @user.email_address,
      subject: "We're now PodRead! Your feed URL has changed"
    )
  end
end
