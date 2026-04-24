# frozen_string_literal: true

# Durable audit row written inside DeactivatesUser's transaction
# (agent-team-k15). Exists so finance/support can answer "when did this
# account shut off?" from the DB without relying on log retention.
class Deactivation < ApplicationRecord
  belongs_to :user

  validates :deactivated_at, presence: true
end
