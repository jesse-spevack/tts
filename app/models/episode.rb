class Episode < ApplicationRecord
  include SynthesizableContent

  has_prefix_id :ep

  belongs_to :podcast
  belongs_to :user
  belongs_to :mpp_payment, optional: true
  has_one :llm_usage, dependent: :destroy
  has_one :tts_usage, as: :usable, dependent: :destroy

  enum :status, { pending: "pending", preparing: "preparing", processing: "processing", complete: "complete", failed: "failed" }
  enum :source_type, { file: 0, url: 1, paste: 2, extension: 3, email: 4 }

  validates :title, presence: true, length: { maximum: 255 }
  validates :source_url, presence: true, if: :source_url_required?
  validates :source_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, if: -> { source_url.present? }
  validates :author, presence: true, length: { maximum: 255 }
  validates :description, presence: true, length: { maximum: 1000 }
  validates :duration_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 86_400 }, allow_nil: true

  validates :source_text, presence: { message: "cannot be empty" },
            if: :source_text_required?

  validates :source_text, length: {
              minimum: AppConfig::Content::MIN_LENGTH,
              message: "must be at least %{count} characters"
            },
            if: :source_text_required?,
            allow_blank: true

  validate :content_within_tier_limit, on: :create,
           if: -> { source_text.present? }

  default_scope { where(deleted_at: nil) }
  scope :newest_first, -> { order(created_at: :desc) }

  before_validation :set_default_voice, on: :create

  def soft_delete!
    raise "Episode already deleted" if soft_deleted?

    update!(deleted_at: Time.current)
  end

  def soft_deleted?
    deleted_at.present?
  end

  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  # Google voice string that was (or would be) used by TTS.
  # Returns the stamped voice if synth has occurred, otherwise the
  # user's current voice preference as a fallback for legacy rows
  # and pre-synth display.
  def effective_voice
    voice.presence || user&.voice
  end

  def audio_url
    GeneratesEpisodeAudioUrl.call(self)
  end

  def download_url
    GeneratesEpisodeDownloadUrl.call(self)
  end

  def broadcast_status_change
    broadcast_replace_to(
      "podcast_#{podcast_id}_episodes",
      target: self,
      partial: "episodes/episode_card",
      locals: { episode: self }
    )
  end

  private

  def source_url_required?
    url? || extension?
  end

  def source_text_required?
    paste? || file? || extension? || email?
  end

  def content_within_tier_limit
    result = ValidatesCharacterLimit.call(user: user, character_count: source_text.length)
    errors.add(:source_text, result.error) if result.failure?
  end

  def set_default_voice
    self.voice ||= user&.voice
  end
end
