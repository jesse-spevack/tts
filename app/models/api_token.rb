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
end
