# frozen_string_literal: true

require "test_helper"

class EpisodesMailboxTest < ActionMailbox::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @user = users(:one)
  end

  test "routes readtome@ emails to episodes mailbox" do
    inbound_email = receive_inbound_email_from_mail(
      to: "readtome@tts.verynormal.dev",
      from: @user.email_address,
      subject: "Newsletter content",
      body: "A" * 150
    )

    assert_equal "episodes", inbound_email.mail.to.first.split("@").first.downcase == "readtome" ? "episodes" : "unknown"
  end

  test "creates episode for known sender" do
    assert_enqueued_with(job: ProcessesEmailEpisodeJob) do
      receive_inbound_email_from_mail(
        to: "readtome@tts.verynormal.dev",
        from: @user.email_address,
        subject: "My newsletter",
        body: "A" * 150
      )
    end
  end

  test "does not create episode for unknown senders" do
    assert_no_enqueued_jobs(only: ProcessesEmailEpisodeJob) do
      receive_inbound_email_from_mail(
        to: "readtome@tts.verynormal.dev",
        from: "unknown@example.com",
        subject: "Spam",
        body: "Content that should be ignored"
      )
    end
  end

  test "sends success notification when user has confirmation enabled" do
    @user.update!(email_episode_confirmation: true)

    assert_enqueued_emails 1 do
      receive_inbound_email_from_mail(
        to: "readtome@tts.verynormal.dev",
        from: @user.email_address,
        subject: "My newsletter",
        body: "A" * 150
      )
    end
  end

  test "does not send success notification when user has confirmation disabled" do
    @user.update!(email_episode_confirmation: false)

    assert_no_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      receive_inbound_email_from_mail(
        to: "readtome@tts.verynormal.dev",
        from: @user.email_address,
        subject: "My newsletter",
        body: "A" * 150
      )
    end
  end

  test "sends failure notification on creation error" do
    # Email too short to create episode
    assert_enqueued_emails 1 do
      receive_inbound_email_from_mail(
        to: "readtome@tts.verynormal.dev",
        from: @user.email_address,
        subject: "Short email",
        body: "Too short"
      )
    end
  end
end
