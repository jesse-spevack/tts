# frozen_string_literal: true

module Mpp
  class GeneratesReceipt
    include StructuredLogging

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(tx_hash:, mpp_payment:)
      @tx_hash = tx_hash
      @mpp_payment = mpp_payment
    end

    def call
      sig_data = "#{tx_hash}|#{mpp_payment.public_id}"
      sig = OpenSSL::HMAC.hexdigest("SHA256", AppConfig::Mpp::SECRET_KEY, sig_data)

      receipt = "tx=#{tx_hash}, payment=#{mpp_payment.public_id}, sig=#{sig}"
      header_value = receipt

      Result.success(
        receipt: receipt,
        header_value: header_value
      )
    end

    private

    attr_reader :tx_hash, :mpp_payment
  end
end
