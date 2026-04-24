class TtsUsage < ApplicationRecord
  # cost_cents is an integer — intentional divergence from
  # LlmUsage.cost_cents, which uses decimal(10, 4) for sub-cent LLM token
  # math. TTS COGS round cleanly at the cent boundary (COST_CENTS_PER_MILLION
  # is {standard: 400, premium: 3_000}, both whole cents per million chars)
  # and aligns with Mpp::PRICE_PREMIUM_CENTS plus every other _cents column
  # in the schema. Keep it integer; convert at the edges if fractional-cent
  # math is ever needed here. (agent-team-a23y)
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
