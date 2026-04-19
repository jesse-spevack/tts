# frozen_string_literal: true

require "test_helper"

class Mpp::GeneratesReceiptTest < ActiveSupport::TestCase
  setup do
    @mpp_payment = mpp_payments(:completed)
    @tx_hash = "0xabc123def456789"
  end

  test "returns a successful Result" do
    result = Mpp::GeneratesReceipt.call(
      tx_hash: @tx_hash,
      mpp_payment: @mpp_payment
    )

    assert result.success?
  end

  test "result contains the receipt string" do
    result = Mpp::GeneratesReceipt.call(
      tx_hash: @tx_hash,
      mpp_payment: @mpp_payment
    )

    assert result.data[:receipt].present?
    assert result.data[:receipt].is_a?(String)
  end

  test "receipt contains the tx_hash" do
    result = Mpp::GeneratesReceipt.call(
      tx_hash: @tx_hash,
      mpp_payment: @mpp_payment
    )

    receipt = result.data[:receipt]
    assert_includes receipt, @tx_hash
  end

  test "receipt is HMAC-signed" do
    result = Mpp::GeneratesReceipt.call(
      tx_hash: @tx_hash,
      mpp_payment: @mpp_payment
    )

    receipt = result.data[:receipt]
    # The receipt should contain a signature component
    assert_match(/sig=/, receipt)
  end

  test "receipt HMAC changes when tx_hash changes" do
    result1 = Mpp::GeneratesReceipt.call(
      tx_hash: "0xaaa111",
      mpp_payment: @mpp_payment
    )

    result2 = Mpp::GeneratesReceipt.call(
      tx_hash: "0xbbb222",
      mpp_payment: @mpp_payment
    )

    assert_not_equal result1.data[:receipt], result2.data[:receipt]
  end

  test "receipt can be serialized to a Payment-Receipt header value" do
    result = Mpp::GeneratesReceipt.call(
      tx_hash: @tx_hash,
      mpp_payment: @mpp_payment
    )

    header_value = result.data[:header_value]
    assert header_value.present?
    # Should contain the tx_hash and a signature
    assert_includes header_value, @tx_hash
    assert_match(/sig=/, header_value)
  end

  test "receipt includes payment prefix_id" do
    result = Mpp::GeneratesReceipt.call(
      tx_hash: @tx_hash,
      mpp_payment: @mpp_payment
    )

    receipt = result.data[:receipt]
    assert_includes receipt, @mpp_payment.prefix_id
  end
end
