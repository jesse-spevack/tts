class Podcast < ApplicationRecord
  has_many :podcast_memberships, dependent: :destroy
  has_many :users, through: :podcast_memberships
  has_many :episodes, dependent: :destroy

  validates :podcast_id, presence: true, uniqueness: true

  before_validation :generate_podcast_id, on: :create

  def feed_url
    return nil unless podcast_id.present?

    bucket = ENV.fetch("GOOGLE_CLOUD_BUCKET", "verynormal-tts-podcast")
    "https://storage.googleapis.com/#{bucket}/podcasts/#{podcast_id}/feed.xml"
  end

  private

  def generate_podcast_id
    self.podcast_id ||= "podcast_#{SecureRandom.hex(8)}"
  end
end
