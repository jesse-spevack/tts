class SentMessage < ApplicationRecord
  belongs_to :user

  validates :message_type, presence: true
  validates :message_type, uniqueness: { scope: :user_id }
end
