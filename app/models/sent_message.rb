class SentMessage < ApplicationRecord
  FIRST_EPISODE_READY = "first_episode_ready"

  belongs_to :user

  validates :message_type, presence: true
  validates :message_type, uniqueness: { scope: :user_id }
end
