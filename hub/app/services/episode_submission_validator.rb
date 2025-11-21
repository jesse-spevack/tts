class EpisodeSubmissionValidator
  MAX_CHARACTERS_FREE = 10_000
  MAX_CHARACTERS_BASIC = 25_000
  MAX_CHARACTERS_PLUS_PREMIUM = 50_000

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
    case
    when user.unlimited? then nil
    when user.premium? || user.plus? then MAX_CHARACTERS_PLUS_PREMIUM
    when user.basic? then MAX_CHARACTERS_BASIC
    else MAX_CHARACTERS_FREE
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
