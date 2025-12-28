# frozen_string_literal: true

class Outcome
  attr_reader :message, :error, :data

  def initialize(success:, message:, error:, data:)
    @success = success
    @message = message
    @error = error
    @data = data
    freeze
  end

  def self.success(message = nil, **data)
    new(success: true, message: message, error: nil, data: data.empty? ? nil : data)
  end

  def self.failure(message, error: nil)
    new(success: false, message: message, error: error, data: nil)
  end

  def success?
    @success
  end

  def failure?
    !@success
  end

  def flash_type
    success? ? :notice : :alert
  end
end
