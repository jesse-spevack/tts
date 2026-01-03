# frozen_string_literal: true

class ValidatesCharacterLimit
  def self.call(user:, character_count:)
    new(user: user, character_count: character_count).call
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
    "exceeds your plan's #{limit.to_fs(:delimited)} character limit " \
    "(#{character_count.to_fs(:delimited)} characters)"
  end
end
