# frozen_string_literal: true

class AddNeedsReviewAndRefundErrorToMppPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :mpp_payments, :needs_review, :boolean, default: false, null: false
    add_column :mpp_payments, :refund_error, :text
  end
end
