# frozen_string_literal: true

class Narration < ApplicationRecord
  include SynthesizableContent

  has_prefix_id :nar

  belongs_to :mpp_payment
  has_one :tts_usage, as: :usable, dependent: :destroy

  enum :source_type, { url: 0, text: 1 }
  enum :status, { pending: "pending", preparing: "preparing", processing: "processing", complete: "complete", failed: "failed" }

  validates :title, presence: true
  validates :source_type, presence: true
  validates :expires_at, presence: true

  before_validation :set_default_voice, on: :create

  # Duck-type compatibility with Episode for ProcessesWithLlm prompt selection.
  # Text narrations use the paste prompt; URL narrations use the URL prompt.
  def paste?
    text?
  end

  def email?
    false
  end

  def expired?
    expires_at < Time.current
  end

  private

  def set_default_voice
    self.voice ||= Voice::DEFAULT_CHIRP
  end
end
