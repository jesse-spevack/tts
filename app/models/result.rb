# frozen_string_literal: true

class Result
  attr_reader :data, :error

  def initialize(success:, data:, error:)
    @success = success
    @data = data
    @error = error
    freeze
  end

  def self.success(data)
    new(success: true, data: data, error: nil)
  end

  def self.failure(error)
    new(success: false, data: nil, error: error)
  end

  def success?
    @success
  end

  def failure?
    !@success
  end
end
