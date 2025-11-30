class LlmUsage < ApplicationRecord
  belongs_to :episode

  validates :model_id, presence: true
  validates :provider, presence: true
  validates :input_tokens, presence: true
  validates :output_tokens, presence: true

  def cost_dollars
    (cost_cents || 0) / 100.0
  end
end
