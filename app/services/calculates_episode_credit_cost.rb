# frozen_string_literal: true

class CalculatesEpisodeCreditCost
  def self.call(source_text_length:, voice:)
    new(source_text_length: source_text_length, voice: voice).call
  end

  def initialize(source_text_length:, voice:)
    @source_text_length = source_text_length
    @voice = voice
  end

  def call
    return 1 if source_text_length <= 20_000
    return 1 if voice.standard?

    2
  end

  private

  attr_reader :source_text_length, :voice
end
