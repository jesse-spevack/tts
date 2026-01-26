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

  test "episode_failed includes friendly error in body" do
    email = EmailEpisodeMailer.episode_failed(user: @user, error: "LLM processing failed")

    # Should show friendly message, not raw error
    assert_includes email.html_part.body.to_s, "We had trouble processing your content"
    assert_includes email.text_part.body.to_s, "We had trouble processing your content"
  end

  test "episode_failed uses default message for unknown errors" do
    email = EmailEpisodeMailer.episode_failed(user: @user, error: "Some unknown error")

    assert_includes email.html_part.body.to_s, "Something went wrong processing your email"
    assert_includes email.text_part.body.to_s, "Something went wrong processing your email"
  end
end
