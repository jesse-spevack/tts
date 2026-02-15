# frozen_string_literal: true

class ProcessingEstimate < ApplicationRecord
  validates :base_seconds, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :microseconds_per_character, presence: true, numericality: { greater_than: 0 }
  validates :episode_count, presence: true, numericality: { greater_than: 0 }
end
