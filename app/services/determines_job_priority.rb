# frozen_string_literal: true

class DeterminesJobPriority
  PREMIUM_PRIORITY = 0
  FREE_PRIORITY = 10

  def self.call(user:)
    user.premium? ? PREMIUM_PRIORITY : FREE_PRIORITY
  end
end
