# frozen_string_literal: true

class CleanupExpiredDeviceCodesJob < ApplicationJob
  queue_as :default

  def perform
    count = DeviceCode.where("expires_at < ?", Time.current).delete_all
    Rails.logger.info "[CleanupExpiredDeviceCodesJob] Deleted #{count} expired device codes"
  end
end
