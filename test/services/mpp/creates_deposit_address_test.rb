# frozen_string_literal: true

require "test_helper"

class Mpp::CreatesDepositAddressTest < ActiveSupport::TestCase
  setup do
    @amount_cents = 100
    @currency = "usd"
    Stripe.api_key = "sk_test_fake"
  end

  test "calls Stripe::PaymentIntent.create with correct params" do
    deposit_address = "0xdeposit_address_abc123"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .with(body: hash_including(
        "payment_method_types[]" => "crypto",
        "amount" => @amount_cents.to_s,
        "currency" => @currency
      ))
      .to_return(status: 200, body: {
        id: "pi_test_123",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: deposit_address }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )

    assert result.success?
  end

  test "lowercases the extracted deposit address (canonical form)" do
    # Stripe may return EIP-55 checksummed (mixed-case) addresses; cache
    # keys and Transfer-log comparisons happen in lowercase.
    mixed_case = "0xAbCdEf1234567890aBcDeF1234567890ABCDEF12"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_case_norm",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: mixed_case }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )

    assert_equal mixed_case.downcase, result.data[:deposit_address]
  end

  test "extracts deposit address from next_action crypto_display_details" do
    deposit_address = "0xdeposit_address_abc123"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_123",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: deposit_address }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )

    assert_equal deposit_address, result.data[:deposit_address]
  end

  test "returns payment_intent_id in result" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_456",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: "0xaddr" }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )

    assert_equal "pi_test_456", result.data[:payment_intent_id]
  end

  test "caches the payment_intent_id keyed by deposit_address" do
    deposit_address = "0xcached_address_789"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_cache",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: deposit_address }
            }
          }
        }
      }.to_json)

    Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )

    # Keyed by deposit_address (the on-chain Transfer-log recipient).
    cached = Rails.cache.read("mpp:deposit_address:#{deposit_address}")
    assert_equal "pi_test_cache", cached
  end

  test "does not persist any MppPayment rows (single responsibility)" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_no_write",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: "0xsingle_resp" }
            }
          }
        }
      }.to_json)

    assert_no_difference "MppPayment.count" do
      Mpp::CreatesDepositAddress.call(
        amount_cents: @amount_cents,
        currency: @currency
      )
    end
  end

  test "fails when Stripe response is missing deposit address" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_no_addr",
        status: "requires_payment_method"
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )

    assert result.failure?
  end

  test "fails when Stripe returns unexpected structure without next_action" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_bad",
        status: "requires_payment_method"
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )

    assert result.failure?
  end

  test "fails when Stripe returns unexpected structure without tempo address" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_no_tempo",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              ethereum: { address: "0xeth_addr" }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )

    assert result.failure?
  end

  test "fails when Stripe API call raises an error" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 402, body: {
        error: { message: "Your card was declined", type: "card_error" }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )

    assert result.failure?
  end

  test "includes payment_method_types crypto and deposit mode in Stripe call" do
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_mode",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: "0xaddr" }
            }
          }
        }
      }.to_json)

    Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency
    )

    assert_requested(:post, "https://api.stripe.com/v1/payment_intents") { |req|
      body = URI.decode_www_form(req.body).to_h
      body["payment_method_types[]"] == "crypto"
    }
  end

  test "succeeds when supported_tokens contains the expected contract address" do
    expected = "0x20c000000000000000000000b9537d11c60e8b50"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_supports_match",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: {
                address: "0xmatch",
                supported_tokens: [
                  { token_currency: "usdc", token_contract_address: expected }
                ]
              }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      expected_token_address: expected
    )

    assert result.success?, "Matching contract should pass: #{result.error}"
  end

  test "succeeds when Stripe response omits supported_tokens (tolerant default)" do
    # Tolerant default lets older fixtures pass; only an affirmative
    # mismatch fails. Strict mode (MPP_REQUIRE_SUPPORTED_TOKENS=1) flips this.
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_supports_absent",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: "0xabsent" }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      expected_token_address: "0x20c000000000000000000000b9537d11c60e8b50"
    )

    assert result.success?, "Missing supported_tokens must not fail-closed: #{result.error}"
  end

  test "fails when Stripe returns supported_tokens that do not include the expected contract (drift guard)" do
    # Stripe drift (network enum change, new default token) — the 402 must
    # not reach the client with a doomed deposit address.
    expected = "0x20c000000000000000000000b9537d11c60e8b50"
    drifted  = "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_drift",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: {
                address: "0xdrift",
                supported_tokens: [
                  { token_currency: "usdc", token_contract_address: drifted }
                ]
              }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      expected_token_address: expected
    )

    assert result.failure?, "Drifted supported_tokens must trigger failure"
    assert_match(/does not support expected token/, result.error)
    assert_match(/#{Regexp.escape(expected)}/, result.error)
  end

  test "strict mode fails when supported_tokens is absent" do
    # MPP_REQUIRE_SUPPORTED_TOKENS=1: a Stripe regression that drops the
    # field surfaces at provision time, not silently after the 402.
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_strict_absent",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: "0xstrict_absent" }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      expected_token_address: "0x20c000000000000000000000b9537d11c60e8b50",
      require_supported_tokens: true
    )

    assert result.failure?, "Strict mode must fail-closed on missing supported_tokens"
    assert_match(/missing supported_tokens/, result.error)
  end

  test "strict mode succeeds when supported_tokens is present and matches" do
    expected = "0x20c000000000000000000000b9537d11c60e8b50"

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_strict_match",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: {
                address: "0xstrict_match",
                supported_tokens: [
                  { token_currency: "usdc", token_contract_address: expected }
                ]
              }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      expected_token_address: expected,
      require_supported_tokens: true
    )

    assert result.success?, "Strict mode must succeed when token matches: #{result.error}"
  end

  test "drift guard is case-insensitive on the contract address" do
    expected_lower = "0x20c000000000000000000000b9537d11c60e8b50"
    expected_upper = expected_lower.upcase.sub(/\A0X/, "0x")

    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_case",
        next_action: {
          crypto_display_details: {
            deposit_addresses: {
              tempo: {
                address: "0xcase",
                supported_tokens: [
                  { token_currency: "usdc", token_contract_address: expected_upper }
                ]
              }
            }
          }
        }
      }.to_json)

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: @amount_cents,
      currency: @currency,
      expected_token_address: expected_lower
    )

    assert result.success?, "Case difference must not trigger drift failure: #{result.error}"
  end
end
