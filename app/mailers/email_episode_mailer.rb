# frozen_string_literal: true

class EmailEpisodeMailer < ApplicationMailer
  def episode_created(episode:)
    @episode = episode
    @user = episode.user
    @feed_url = episode.podcast.feed_url

    mail(
      to: @user.email_address,
      subject: "Your email is being converted to audio"
    )
  end

  def episode_failed(user:, error:)
    @user = user
    @error = error

    mail(
      to: @user.email_address,
      subject: "Unable to process your email"
    )
  end
end
