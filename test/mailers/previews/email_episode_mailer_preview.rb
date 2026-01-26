# frozen_string_literal: true

class EmailEpisodeMailerPreview < ActionMailer::Preview
  def episode_created
    episode = Episode.first || create_sample_episode
    EmailEpisodeMailer.episode_created(episode: episode)
  end

  def episode_failed
    user = User.first || User.create!(email_address: "preview@example.com")
    EmailEpisodeMailer.episode_failed(user: user, error: "Content must be at least 100 characters")
  end

  private

  def create_sample_episode
    user = User.first || User.create!(email_address: "preview@example.com")
    podcast = user.podcasts.first || user.primary_podcast
    podcast.episodes.create!(
      user: user,
      title: "Sample Episode",
      author: "Sample Author",
      description: "A sample episode for preview",
      source_type: :email,
      source_text: "Sample content",
      status: :processing
    )
  end
end
