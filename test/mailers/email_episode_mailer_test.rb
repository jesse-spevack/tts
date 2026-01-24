# frozen_string_literal: true

require "test_helper"

class EmailEpisodeMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:one)
    @episode = episodes(:one)
  end

  test "episode_created sends to user" do
    email = EmailEpisodeMailer.episode_created(episode: @episode)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ @user.email_address ], email.to
    assert_equal "Your email is being converted to audio", email.subject
  end

  test "episode_created includes feed URL in body" do
    email = EmailEpisodeMailer.episode_created(episode: @episode)

    assert_includes email.html_part.body.to_s, @episode.podcast.feed_url
    assert_includes email.text_part.body.to_s, @episode.podcast.feed_url
  end

  test "episode_failed sends to user" do
    email = EmailEpisodeMailer.episode_failed(user: @user, error: "Content too short")

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ @user.email_address ], email.to
    assert_equal "Unable to process your email", email.subject
  end

  test "episode_failed includes error in body" do
    email = EmailEpisodeMailer.episode_failed(user: @user, error: "Content too short")

    assert_includes email.html_part.body.to_s, "Content too short"
    assert_includes email.text_part.body.to_s, "Content too short"
  end
end
