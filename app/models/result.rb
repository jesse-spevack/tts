# frozen_string_literal: true

class Result
  attr_reader :data, :error, :message

  def initialize(success:, data:, error:, message: nil)
    @success = success
    @data = data
    @error = error
    @message = message
    freeze
  end

  def self.success(data = nil, message: nil, **kwargs)
    actual_data = data.nil? && kwargs.any? ? kwargs : data
    new(success: true, data: actual_data, error: nil, message: message)
  end

  def self.failure(error, message: nil)
    new(success: false, data: nil, error: error, message: message || error)
  end

  def success?
    @success
  end

  def failure?
    !@success
  end

  def flash_type
    @success ? :notice : :alert
  end
end
