class Episode < ApplicationRecord
  has_prefix_id :ep

  belongs_to :podcast
  belongs_to :user
  has_one :llm_usage, dependent: :destroy

  delegate :voice, to: :user

  enum :status, { pending: "pending", processing: "processing", complete: "complete", failed: "failed" }
  enum :source_type, { file: 0, url: 1, paste: 2 }

  validates :title, presence: true, length: { maximum: 255 }
  validates :source_url, presence: true, if: :url?
  validates :source_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }, if: -> { source_url.present? }
  validates :author, presence: true, length: { maximum: 255 }
  validates :description, presence: true, length: { maximum: 1000 }
  validates :duration_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 86_400 }, allow_nil: true

  validates :source_text, presence: { message: "cannot be empty" },
            if: -> { paste? || file? }

  validates :source_text, length: {
              minimum: AppConfig::Content::MIN_LENGTH,
              message: "must be at least %{count} characters"
            },
            if: -> { paste? || file? },
            allow_blank: true

  validate :content_within_tier_limit, on: :create,
           if: -> { source_text.present? }

  default_scope { where(deleted_at: nil) }
  scope :newest_first, -> { order(created_at: :desc) }

  def soft_delete!
    raise "Episode already deleted" if soft_deleted?

    update!(deleted_at: Time.current)
  end

  def soft_deleted?
    deleted_at.present?
  end

  # Broadcast updates when status changes
  after_update_commit :broadcast_status_change, if: :saved_change_to_status?

  def audio_url
    GeneratesEpisodeAudioUrl.call(self)
  end

  def download_url
    GenerateEpisodeDownloadUrl.call(self)
  end

  private

  def content_within_tier_limit
    max_chars = user.character_limit
    return unless max_chars

    if source_text.length > max_chars
      errors.add(:source_text,
        "exceeds your plan's #{max_chars.to_fs(:delimited)} character limit " \
        "(#{source_text.length.to_fs(:delimited)} characters)")
    end
  end

  def broadcast_status_change
    broadcast_replace_to(
      "podcast_#{podcast_id}_episodes",
      target: self,
      partial: "episodes/episode_card",
      locals: { episode: self }
    )
  end
end
