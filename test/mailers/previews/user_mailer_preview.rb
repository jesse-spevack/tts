# Preview all emails at http://localhost:3000/rails/mailers/user_mailer
class UserMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/user_mailer/first_episode_ready
  def first_episode_ready
    episode = Episode.new(
      id: 1,
      title: "My First Podcast Episode",
      user: User.new(email_address: "preview@example.com"),
      podcast: Podcast.new(podcast_id: "podcast_preview123")
    )

    UserMailer.first_episode_ready(episode: episode)
  end

  # Preview this email at http://localhost:3000/rails/mailers/user_mailer/feed_url_migration
  def feed_url_migration
    user = User.joins(podcasts: :episodes)
               .where(episodes: { status: :complete })
               .first || User.first

    UserMailer.feed_url_migration(user: user)
  end
end
