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

  # User.default_scope hides soft-deleted users, so belongs_to :user returns
  # nil once the account has been soft-deleted. has_many :api_tokens,
  # dependent: :destroy means hard-delete cascades the token row away, so in
  # practice user.nil? here means soft-deleted.
  def belongs_to_soft_deleted_user?
    user.nil?
  end
end
