class Episode < ApplicationRecord
  belongs_to :podcast

  enum :status, { pending: "pending", processing: "processing", complete: "complete", failed: "failed" }

  validates :title, presence: true, length: { maximum: 255 }
  validates :author, presence: true, length: { maximum: 255 }
  validates :description, presence: true, length: { maximum: 1000 }

  scope :newest_first, -> { order(created_at: :desc) }

  def audio_url
    return nil unless complete? && gcs_episode_id.present?

    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    podcast_id = podcast.podcast_id
    "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast_id}/episodes/#{gcs_episode_id}.mp3"
  end
end
