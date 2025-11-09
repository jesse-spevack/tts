class User < ApplicationRecord
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :with_valid_auth_token, -> {
    where.not(auth_token: nil)
         .where("auth_token_expires_at > ?", Time.current)
  }
end
