require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "first_episode_ready sends to user email" do
    episode = episodes(:two)  # This fixture has status: complete
    mail = UserMailer.first_episode_ready(episode: episode)

    assert_equal [ episode.user.email_address ], mail.to
  end

  test "first_episode_ready has correct subject" do
    episode = episodes(:two)
    mail = UserMailer.first_episode_ready(episode: episode)

    assert_equal "Your first episode is ready 🎧", mail.subject
  end

  test "first_episode_ready includes episode title" do
    episode = episodes(:two)
    mail = UserMailer.first_episode_ready(episode: episode)

    assert_match episode.title, mail.body.encoded
  end

  test "first_episode_ready includes RSS feed URL" do
    episode = episodes(:two)
    mail = UserMailer.first_episode_ready(episode: episode)

    assert_match episode.podcast.feed_url, mail.body.encoded
  end

  test "first_episode_ready includes help page link" do
    episode = episodes(:two)
    mail = UserMailer.first_episode_ready(episode: episode)

    assert_match "help/add-rss-feed", mail.body.encoded
  end
end
