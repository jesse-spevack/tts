# frozen_string_literal: true

class ValidatesCharacterLimit
  ERROR_PREFIX = "exceeds your plan's"

  def self.call(user:, character_count:)
    new(user: user, character_count: character_count).call
  end

  # True when an episode's error_message was produced by this validator —
  # used by the episode card to surface the split-and-paste tip.
  def self.error?(error_message)
    error_message.to_s.start_with?(ERROR_PREFIX)
  end

  def initialize(user:, character_count:)
    @user = user
    @character_count = character_count
  end

  def call
    return Result.success if limit.nil?
    return Result.success if character_count <= limit

    Result.failure(error_message)
  end

  private

  attr_reader :user, :character_count

  def limit
    user.character_limit
  end

  def error_message
    "#{ERROR_PREFIX} #{limit.to_fs(:delimited)} character limit " \
    "(#{character_count.to_fs(:delimited)} characters)"
  end
end
