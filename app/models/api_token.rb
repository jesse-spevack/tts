class ApiToken < ApplicationRecord
  belongs_to :user

  # source distinguishes how the token was issued. Prefix avoids shadowing
  # the :user association with an enum-generated .user scope.
  enum :source, { user: "user", extension: "extension" }, prefix: true

  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }
  scope :user_created, -> { source_user }

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
