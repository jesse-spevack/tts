class DeviceCode < ApplicationRecord
  EXPIRATION = 15.minutes

  belongs_to :user, optional: true

  validates :user_code, presence: true, uniqueness: true
  validates :device_code, presence: true, uniqueness: true
  validates :expires_at, presence: true

  def confirmed?
    confirmed_at.present?
  end

  def expired?
    expires_at < Time.current
  end
end
