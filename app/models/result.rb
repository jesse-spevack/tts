# frozen_string_literal: true

class Result
  attr_reader :data, :error, :message, :code

  def initialize(success:, data:, error:, message: nil, code: nil)
    @success = success
    @data = data
    @error = error
    @message = message
    @code = code
    freeze
  end

  def self.success(data = nil, message: nil, **kwargs)
    actual_data = data.nil? && kwargs.any? ? kwargs : data
    new(success: true, data: actual_data, error: nil, message: message)
  end

  def self.failure(error, message: nil, code: nil)
    new(success: false, data: nil, error: error, message: message || error, code: code)
  end

  def success?
    @success
  end

  def failure?
    !@success
  end
end
