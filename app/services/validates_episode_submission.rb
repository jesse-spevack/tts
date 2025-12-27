# frozen_string_literal: true

class ValidatesEpisodeSubmission
  MAX_CHARACTERS_FREE = 15_000
  MAX_CHARACTERS_PREMIUM = 50_000

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    ValidationResult.success(
      max_characters: max_characters_for_user
    )
  end

  private

  attr_reader :user

  def max_characters_for_user
    case user.tier
    when "free" then MAX_CHARACTERS_FREE
    when "premium" then MAX_CHARACTERS_PREMIUM
    when "unlimited" then nil
    end
  end

  class ValidationResult
    attr_reader :max_characters

    def self.success(max_characters:)
      new(max_characters: max_characters)
    end

    def initialize(max_characters:)
      @max_characters = max_characters
    end

    def unlimited?
      max_characters.nil?
    end
  end
end
