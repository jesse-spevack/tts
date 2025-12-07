class Episode < ApplicationRecord
  has_prefix_id :ep

  belongs_to :podcast
  belongs_to :user
  has_one :llm_usage, dependent: :destroy

  delegate :voice, to: :user

  enum :status, { pending: "pending", processing: "processing", complete: "complete", failed: "failed" }
  enum :source_type, { file: 0, url: 1 }

  validates :title, presence: true, length: { maximum: 255 }
  validates :source_url, presence: true, if: :url?
  validates :source_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, if: -> { source_url.present? }
  validates :author, presence: true, length: { maximum: 255 }
  validates :description, presence: true, length: { maximum: 1000 }
  validates :duration_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 86_400 }, allow_nil: true

  scope :newest_first, -> { order(created_at: :desc) }

  # Broadcast updates when status changes
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  def audio_url
    return nil unless complete? && gcs_episode_id.present?

    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    podcast_id = podcast.podcast_id
    "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast_id}/episodes/#{gcs_episode_id}.mp3"
  end

  def download_url
    GenerateEpisodeDownloadUrl.call(self)
  end

  private

  def broadcast_status_change
    broadcast_replace_to(
      "podcast_#{podcast_id}_episodes",
      target: self,
      partial: "episodes/episode_card",
      locals: { episode: self }
    )
  end
end
