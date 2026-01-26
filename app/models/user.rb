class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :podcast_memberships, dependent: :destroy
  has_many :podcasts, through: :podcast_memberships
  has_many :episodes, dependent: :destroy
  has_many :sent_messages, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
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
    Voice.google_voice_for(voice_preference, is_unlimited: unlimited?)
  end

  def available_voices
    AppConfig::Tiers.voices_for(effective_tier)
  end

  def character_limit
    return nil if unlimited?
    return AppConfig::Tiers::PREMIUM_CHARACTER_LIMIT if premium?
    AppConfig::Tiers::FREE_CHARACTER_LIMIT
  end

  def email
    email_address
  end

  def primary_podcast
    podcasts.first || CreatesDefaultPodcast.call(user: self)
  end

  # Email episodes feature
  def enable_email_episodes!
    EnablesEmailEpisodes.call(user: self)
  end

  def disable_email_episodes!
    DisablesEmailEpisodes.call(user: self)
  end

  def regenerate_email_ingest_token!
    RegeneratesEmailIngestToken.call(user: self)
  end

  def email_ingest_address
    GeneratesEmailIngestAddress.call(user: self)
  end

  private

  def effective_tier
    return "unlimited" if unlimited?
    return "premium" if premium?
    "free"
  end
end
