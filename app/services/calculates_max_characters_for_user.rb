# frozen_string_literal: true

class CalculatesMaxCharactersForUser
  def self.call(user:)
    case user.tier
    when "free" then ValidatesEpisodeSubmission::MAX_CHARACTERS_FREE
    when "premium" then ValidatesEpisodeSubmission::MAX_CHARACTERS_PREMIUM
    when "unlimited" then nil
    end
  end
end
