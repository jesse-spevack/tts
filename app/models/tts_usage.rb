class TtsUsage < ApplicationRecord
  SOURCES = %w[actual estimate].freeze
  VOICE_TIERS = %w[standard premium].freeze

  belongs_to :usable, polymorphic: true

  validates :provider, presence: true
  validates :voice_id, presence: true
  validates :voice_tier, presence: true, inclusion: { in: VOICE_TIERS }
  validates :character_count, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :cost_cents, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :source, presence: true, inclusion: { in: SOURCES }
end
