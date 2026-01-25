class ApiToken < ApplicationRecord
  TOKEN_PREFIX = Rails.env.production? ? "pk_live_" : "pk_test_"

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  # Virtual attribute to hold the plain token temporarily after generation
  attr_accessor :plain_token

  # Generate a new API token for a user
  # Revokes any existing active tokens for the user first
  # Returns the ApiToken record with plain_token accessible ONCE
  def self.generate_for(user)
    # Revoke any existing active tokens for this user
    user.api_tokens.active.find_each(&:revoke!)

    # Generate a secure random token
    raw_token = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"

    # Create the token record
    token = create!(
      user: user,
      token_digest: hash_token(raw_token)
    )

    # Set the plain token so it can be returned to the caller once
    token.plain_token = raw_token
    token
  end

  # Find an ApiToken by its plain token value
  # Returns the ApiToken if valid and not revoked, nil otherwise
  def self.find_by_token(plain_token)
    return nil if plain_token.blank?

    digest = hash_token(plain_token)
    active.find_by(token_digest: digest)
  end

  # Find the active token for a user (if any)
  def self.active_token_for(user)
    user.api_tokens.active.first
  end

  # Revoke this token
  def revoke!
    update!(revoked_at: Time.current)
  end

  # Check if this token is revoked
  def revoked?
    revoked_at.present?
  end

  # Check if this token is active (not revoked)
  def active?
    !revoked?
  end

  # Hash a plain token using HMAC-SHA256 with application secret
  # This provides defense-in-depth against rainbow table attacks if DB is compromised
  def self.hash_token(plain_token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.credentials.secret_key_base, plain_token)
  end

  private_class_method :hash_token
end
