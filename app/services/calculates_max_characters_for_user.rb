# frozen_string_literal: true

class CalculatesMaxCharactersForUser
  def self.call(user:)
    AppConfig::Tiers.character_limit_for(user.tier)
  end
end
