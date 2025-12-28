class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :podcast_memberships, dependent: :destroy
  has_many :podcasts, through: :podcast_memberships
  has_many :episodes, dependent: :destroy
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
    if voice_preference.present?
      voice_data = Voice.find(voice_preference)
      return voice_data[:google_voice] if voice_data
    end
    unlimited? ? Voice::DEFAULT_CHIRP : Voice::DEFAULT_STANDARD
  end

  def available_voices
    AppConfig::Tiers.voices_for(tier)
  end

  def email
    email_address
  end
end
