class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :podcast_memberships, dependent: :destroy
  has_many :podcasts, through: :podcast_memberships
  has_many :episodes, dependent: :destroy
  has_many :sent_messages, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :device_codes, dependent: :destroy
  has_many :oauth_access_grants,
    class_name: "Doorkeeper::AccessGrant",
    foreign_key: :resource_owner_id,
    dependent: :destroy
  has_many :oauth_access_tokens,
    class_name: "Doorkeeper::AccessToken",
    foreign_key: :resource_owner_id,
    dependent: :destroy
  has_one :credit_balance, dependent: :destroy
  has_many :credit_transactions, dependent: :destroy

  enum :account_type, { standard: 0, complimentary: 1, unlimited: 2 }, default: :standard

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :voice_preference, inclusion: { in: Voice::ALL }, allow_nil: true

  scope :with_valid_auth_token, -> {
    where.not(auth_token: nil)
         .where("auth_token_expires_at > ?", Time.current)
  }
  scope :active, -> { where(active: true) }

  def deactivated?
    !active?
  end

  def premium?
    complimentary? || unlimited?
  end

  def free?
    standard? && !has_credits?
  end

  def credit_user?
    has_credits? && !premium?
  end

  def paid?
    premium? || credit_user?
  end

  # Single predicate for "this user sees the credit-cost preview" (agent-team-gq88).
  #
  # Used on both the view (new-episode form) and the cost_preview endpoint to
  # prevent divergence. A user is on the credit path iff:
  #   - They are NOT premium (no active subscription, not complimentary, not
  #     unlimited) — !premium? covers all three.
  #   - They have EVER purchased credits — credit_balance.present? captures
  #     users whose balance is currently zero but who are still credit-path
  #     (they'll see the "Buy more" CTA).
  #
  # This intentionally differs from credit_user? which additionally requires
  # balance > 0. A zero-balance credit user still belongs on the credit path:
  # they should see the preview with a "not enough credits" state, not the
  # free-tier copy.
  def on_credit_path?
    !premium? && credit_balance.present?
  end

  def voice
    Voice.google_voice_for(voice_preference, is_premium: premium? || credit_user?)
  end

  def available_voices
    AppConfig::Tiers.voices_for(effective_tier)
  end

  def character_limit
    return nil if unlimited?
    return AppConfig::Tiers::EPISODE_CHARACTER_LIMIT if premium? || credit_user?
    AppConfig::Tiers::FREE_CHARACTER_LIMIT
  end

  def credits_remaining
    credit_balance&.balance || 0
  end

  def has_credits?
    credits_remaining > 0
  end

  def email
    email_address
  end

  def primary_podcast
    podcasts.first || CreatesDefaultPodcast.call(user: self)
  end

  def email_ingest_address
    GeneratesEmailIngestAddress.call(user: self)
  end

  def effective_tier
    return "unlimited" if unlimited?
    return "premium" if premium? || credit_user?
    "free"
  end
end
