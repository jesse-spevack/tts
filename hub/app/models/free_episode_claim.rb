class FreeEpisodeClaim < ApplicationRecord
  belongs_to :user
  belongs_to :episode

  validates :claimed_at, presence: true

  scope :active, -> { where(released_at: nil) }
end
