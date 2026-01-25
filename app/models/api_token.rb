class ApiToken < ApplicationRecord
  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  # Virtual attribute to hold the plain token temporarily after generation
  attr_accessor :plain_token

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
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, plain_token)
  end

  private_class_method :hash_token
end
