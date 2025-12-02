class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :podcast_memberships, dependent: :destroy
  has_many :podcasts, through: :podcast_memberships
  has_many :sent_messages, dependent: :destroy

  enum :tier, { free: 0, premium: 1, unlimited: 2 }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :with_valid_auth_token, -> {
    where.not(auth_token: nil)
         .where("auth_token_expires_at > ?", Time.current)
  }

  def voice_name
    if unlimited?
      "en-GB-Chirp3-HD-Enceladus"
    else
      "en-GB-Standard-D"
    end
  end

  def email
    email_address
  end
end
