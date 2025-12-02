class SentMessage < ApplicationRecord
  belongs_to :user

  validates :message_type, presence: true
  validates :message_type, uniqueness: { scope: :user_id }

  def self.sent?(user:, message_type:)
    exists?(user: user, message_type: message_type)
  end

  def self.record!(user:, message_type:)
    create!(user: user, message_type: message_type)
  end
end
