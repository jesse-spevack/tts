class PodcastMembership < ApplicationRecord
  belongs_to :user
  belongs_to :podcast

  validates :user_id, uniqueness: { scope: :podcast_id }
end
