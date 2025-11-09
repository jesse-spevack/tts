class User < ApplicationRecord
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  def generate_auth_token!
    self.auth_token = SecureRandom.urlsafe_base64
    self.auth_token_expires_at = 30.minutes.from_now
    save!
  end

  def auth_token_valid?
    auth_token.present? && auth_token_expires_at.present? && auth_token_expires_at.future?
  end
end
