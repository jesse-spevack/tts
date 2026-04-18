class ApiToken < ApplicationRecord
  belongs_to :user

  # source distinguishes how the token was issued. Prefix avoids shadowing
  # the :user association with an enum-generated .user scope.
  enum :source, { user: "user", extension: "extension" }, prefix: true

  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true

  scope :active, -> { where(revoked_at: nil) }

  # Virtual attribute to hold the plain token temporarily after generation.
  # Never persisted, never retrievable after the request that minted it.
  # ActiveRecord's default #inspect and #as_json only serialize DB
  # attributes, not instance variables, so the plaintext cannot leak via
  # those paths. Tests below enforce this as a regression guard.
  attr_accessor :plain_token

  # Check if this token is revoked
  def revoked?
    revoked_at.present?
  end

  # Check if this token is active (not revoked)
  def active?
    !revoked?
  end
end
