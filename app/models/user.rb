class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :podcast_memberships, dependent: :destroy
  has_many :podcasts, through: :podcast_memberships
  has_many :episodes, dependent: :destroy
  has_many :sent_messages, dependent: :destroy
  has_one :subscription, dependent: :destroy

  enum :account_type, { standard: 0, complimentary: 1, unlimited: 2 }, default: :standard

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :voice_preference, inclusion: { in: Voice::ALL }, allow_nil: true

  scope :with_valid_auth_token, -> {
    where.not(auth_token: nil)
         .where("auth_token_expires_at > ?", Time.current)
  }

  def premium?
    subscription&.active? || complimentary? || unlimited?
  end

  def free?
    standard? && !subscription&.active?
  end

  def voice
    if voice_preference.present?
      voice_data = Voice.find(voice_preference)
      return voice_data[:google_voice] if voice_data
    end
    unlimited? ? Voice::DEFAULT_CHIRP : Voice::DEFAULT_STANDARD
  end

  def available_voices
    AppConfig::Tiers.voices_for(effective_tier)
  end

  def email
    email_address
  end

  def tier
    return "unlimited" if unlimited?
    return "premium" if premium?
    "free"
  end

  private

  alias_method :effective_tier, :tier
end
