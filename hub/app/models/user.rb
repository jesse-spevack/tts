class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :podcast_memberships, dependent: :destroy
  has_many :podcasts, through: :podcast_memberships

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :with_valid_auth_token, -> {
    where.not(auth_token: nil)
         .where("auth_token_expires_at > ?", Time.current)
  }

  after_create :create_default_podcast

  private

  def create_default_podcast
    CreateDefaultPodcast.call(user: self)
  end
end
