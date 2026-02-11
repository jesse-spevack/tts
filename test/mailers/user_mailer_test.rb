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

  test "feed_url_migration sends to user email" do
    user = users(:two)
    mail = UserMailer.feed_url_migration(user: user)

    assert_equal [ user.email_address ], mail.to
  end

  test "feed_url_migration has correct subject" do
    user = users(:two)
    mail = UserMailer.feed_url_migration(user: user)

    assert_equal "We're now PodRead! Your feed URL has changed", mail.subject
  end

  test "feed_url_migration includes feed URL" do
    user = users(:two)
    mail = UserMailer.feed_url_migration(user: user)

    assert_match user.primary_podcast.feed_url, mail.body.encoded
  end

  test "feed_url_migration includes blog URL" do
    user = users(:two)
    mail = UserMailer.feed_url_migration(user: user)

    assert_match "https://verynormal.info/very-normal-tts-is-now-podread/", mail.body.encoded
  end

  test "feed_url_migration includes rebrand messaging" do
    user = users(:two)
    mail = UserMailer.feed_url_migration(user: user)

    assert_match "PodRead", mail.body.encoded
    assert_match "podread.app", mail.body.encoded
  end
end
