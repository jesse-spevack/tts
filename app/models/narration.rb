# frozen_string_literal: true

class Narration < ApplicationRecord
  has_prefix_id :nar

  belongs_to :mpp_payment

  enum :source_type, { url: 0, text: 1 }
  enum :status, { pending: "pending", preparing: "preparing", processing: "processing", complete: "complete", failed: "failed" }

  validates :title, presence: true
  validates :source_type, presence: true
  validates :expires_at, presence: true

  before_validation :set_default_voice, on: :create

  after_update :refund_mpp_payment_on_failure, if: :should_refund_mpp_payment?

  # Duck-type compatibility with Episode for ProcessesWithLlm prompt selection.
  # Text narrations use the paste prompt; URL narrations use the URL prompt.
  def paste?
    text?
  end

  def email?
    false
  end

  def expired?
    expires_at < Time.current
  end

  private

  def set_default_voice
    self.voice ||= Voice::DEFAULT_CHIRP
  end

  def should_refund_mpp_payment?
    saved_change_to_status? && failed? && mpp_payment.present?
  end

  def refund_mpp_payment_on_failure
    Mpp::RefundsPayment.call(mpp_payment: mpp_payment)
  end
end
