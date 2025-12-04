class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :podcast_memberships, dependent: :destroy
  has_many :podcasts, through: :podcast_memberships
  has_many :sent_messages, dependent: :destroy

  enum :tier, { free: 0, premium: 1, unlimited: 2 }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :voice_preference, inclusion: { in: Voice::ALL }, allow_nil: true

  scope :with_valid_auth_token, -> {
    where.not(auth_token: nil)
         .where("auth_token_expires_at > ?", Time.current)
  }

  def voice
    return Voice.find(voice_preference)[:google_voice] if voice_preference.present?

    unlimited? ? "en-GB-Chirp3-HD-Enceladus" : "en-GB-Standard-D"
  end

  def available_voices
    Voice.for_tier(tier)
  end

  def email
    email_address
  end
end
