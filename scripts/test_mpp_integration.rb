# frozen_string_literal: true

# Manual integration test for MPP payment flow
# Run with: bin/rails runner scripts/test_mpp_integration.rb
#
# Prerequisites:
#   - STRIPE_SECRET_KEY set (sandbox/test key)
#   - Stripe account gated into 2026-03-04.preview
#   - For Tempo RPC test: TEMPO_TEST_TX_HASH env var (optional)

class MppIntegrationTest
  STRIPE_API_VERSION = "2026-03-04.preview"
  POLL_INTERVAL_SECONDS = 2
  POLL_MAX_ATTEMPTS = 15

  def run
    puts "=" * 60
    puts "MPP Integration Test"
    puts "=" * 60
    puts "Stripe key: #{stripe_key_summary}"
    puts "Tempo RPC:  #{AppConfig::Mpp::TEMPO_RPC_URL}"
    puts "=" * 60

    scenario_1_deposit_address
    scenario_2_simulated_deposit
    scenario_3_tempo_rpc
    scenario_4_refund

    puts "\n#{"=" * 60}"
    puts summary
    puts "=" * 60
  end

  private

  def results
    @results ||= {}
  end

  def record(scenario, passed:, detail: "")
    results[scenario] = { passed: passed, detail: detail }
    status = passed ? "PASS" : "FAIL"
    puts "  [#{status}] #{detail}" unless detail.empty?
  end

  def stripe_key_summary
    key = Stripe.api_key
    return "(not set)" if key.nil? || key.empty?

    "#{key[0..6]}...#{key[-4..]}"
  end

  def summary
    passed = results.count { |_, v| v[:passed] }
    total = results.size
    lines = [ "Summary: #{passed}/#{total} scenarios passed\n" ]
    results.each do |name, result|
      status = result[:passed] ? "PASS" : "FAIL"
      lines << "  [#{status}] #{name}"
      lines << "         #{result[:detail]}" unless result[:detail].empty?
    end
    lines.join("\n")
  end

  # ---------- Scenario 1: Deposit address creation ----------

  def scenario_1_deposit_address
    puts "\n--- Scenario 1: Stripe deposit address creation ---"

    result = Mpp::CreatesDepositAddress.call(
      amount_cents: AppConfig::Mpp::PRICE_PREMIUM_CENTS,
      currency: AppConfig::Mpp::CURRENCY,
      recipient: "integration-test"
    )

    if result.success?
      @deposit_address = result.deposit_address
      @payment_intent_id = result.payment_intent_id
      puts "  Deposit address: #{@deposit_address}"
      puts "  PaymentIntent:   #{@payment_intent_id}"
      record("Scenario 1: Deposit address creation", passed: true, detail: "PI #{@payment_intent_id}")
    else
      record("Scenario 1: Deposit address creation", passed: false, detail: result.error)
    end
  rescue Stripe::StripeError => e
    handle_stripe_error("Scenario 1: Deposit address creation", e)
  rescue StandardError => e
    record("Scenario 1: Deposit address creation", passed: false, detail: "#{e.class}: #{e.message}")
  end

  # ---------- Scenario 2: Simulated deposit + capture ----------

  def scenario_2_simulated_deposit
    puts "\n--- Scenario 2: Simulated deposit + capture verification ---"

    pi_id = @payment_intent_id || create_fresh_payment_intent
    unless pi_id
      record("Scenario 2: Simulated deposit", passed: false, detail: "No PaymentIntent available (scenario 1 may have failed)")
      return
    end

    puts "  Using PaymentIntent: #{pi_id}"
    simulate_crypto_deposit(pi_id)
    poll_until_succeeded(pi_id)
  rescue Stripe::StripeError => e
    handle_stripe_error("Scenario 2: Simulated deposit", e)
  rescue StandardError => e
    record("Scenario 2: Simulated deposit", passed: false, detail: "#{e.class}: #{e.message}")
  end

  # ---------- Scenario 3: Tempo testnet RPC ----------

  def scenario_3_tempo_rpc
    puts "\n--- Scenario 3: Tempo testnet RPC verification ---"

    tx_hash = ENV["TEMPO_TEST_TX_HASH"]
    unless tx_hash.present?
      skip_msg = <<~MSG.strip
        Skipped — set TEMPO_TEST_TX_HASH to run. Create one with:
            npx mppx account create
            npx mppx account fund
            # Then send a transfer and pass the tx hash
      MSG
      puts "  #{skip_msg}"
      record("Scenario 3: Tempo RPC verification", passed: true, detail: "Skipped (no TEMPO_TEST_TX_HASH)")
      return
    end

    puts "  Fetching receipt for tx: #{tx_hash}"
    receipt = fetch_transaction_receipt(tx_hash)

    if receipt.nil?
      record("Scenario 3: Tempo RPC verification", passed: false, detail: "Transaction not found")
      return
    end

    status_ok = receipt["status"] == "0x1"
    puts "  Transaction status: #{receipt["status"]} (#{status_ok ? "success" : "reverted"})"

    transfer_events = parse_transfer_logs(receipt)
    if transfer_events.any?
      transfer_events.each do |evt|
        puts "  Transfer found:"
        puts "    Token contract: #{evt[:token]}"
        puts "    Recipient:      #{evt[:recipient]}"
        puts "    Amount (raw):   #{evt[:amount]}"
      end
      record("Scenario 3: Tempo RPC verification", passed: true, detail: "#{transfer_events.size} Transfer event(s) found")
    else
      puts "  No Transfer events in logs"
      record("Scenario 3: Tempo RPC verification", passed: false, detail: "No Transfer events found in #{(receipt["logs"] || []).size} log(s)")
    end
  rescue StandardError => e
    record("Scenario 3: Tempo RPC verification", passed: false, detail: "#{e.class}: #{e.message}")
  end

  # ---------- Scenario 4: Refund ----------

  def scenario_4_refund
    puts "\n--- Scenario 4: Stripe refund ---"

    # Create a fresh PI and simulate deposit so we have a captured payment to refund
    puts "  Creating fresh deposit address..."
    result = Mpp::CreatesDepositAddress.call(
      amount_cents: AppConfig::Mpp::PRICE_PREMIUM_CENTS,
      currency: AppConfig::Mpp::CURRENCY,
      recipient: "integration-test-refund"
    )

    unless result.success?
      record("Scenario 4: Stripe refund", passed: false, detail: "Deposit address creation failed: #{result.error}")
      return
    end

    pi_id = result.payment_intent_id
    puts "  PaymentIntent: #{pi_id}"

    puts "  Simulating deposit..."
    simulate_crypto_deposit(pi_id)

    puts "  Waiting for capture..."
    final_status = poll_payment_intent_status(pi_id)
    unless final_status == "succeeded"
      record("Scenario 4: Stripe refund", passed: false, detail: "PI did not reach succeeded (got: #{final_status})")
      return
    end

    puts "  Issuing refund..."
    refund = Stripe::Refund.create(
      { payment_intent: pi_id },
      { stripe_version: STRIPE_API_VERSION }
    )
    puts "  Refund ID:     #{refund.id}"
    puts "  Refund status: #{refund.status}"

    if refund.status == "succeeded"
      record("Scenario 4: Stripe refund", passed: true, detail: "Refund #{refund.id} succeeded")
    else
      record("Scenario 4: Stripe refund", passed: false, detail: "Refund status: #{refund.status}")
    end
  rescue Stripe::StripeError => e
    handle_stripe_error("Scenario 4: Stripe refund", e)
  rescue StandardError => e
    record("Scenario 4: Stripe refund", passed: false, detail: "#{e.class}: #{e.message}")
  end

  # ---------- Helpers ----------

  def create_fresh_payment_intent
    result = Mpp::CreatesDepositAddress.call(
      amount_cents: AppConfig::Mpp::PRICE_PREMIUM_CENTS,
      currency: AppConfig::Mpp::CURRENCY,
      recipient: "integration-test-scenario2"
    )
    return nil unless result.success?

    result.payment_intent_id
  end

  def simulate_crypto_deposit(payment_intent_id)
    client = Stripe::StripeClient.new(Stripe.api_key)
    response = client.raw_request(
      :post,
      "/v1/test_helpers/payment_intents/#{payment_intent_id}/simulate_crypto_deposit",
      opts: { api_version: STRIPE_API_VERSION }
    )
    parsed = JSON.parse(response.http_body)
    puts "  Simulated deposit — PI status: #{parsed["status"]}"
    parsed
  end

  def poll_until_succeeded(payment_intent_id)
    final_status = poll_payment_intent_status(payment_intent_id)

    if final_status == "succeeded"
      puts "  PaymentIntent reached 'succeeded'"
      record("Scenario 2: Simulated deposit", passed: true, detail: "PI #{payment_intent_id} succeeded")
    else
      record("Scenario 2: Simulated deposit", passed: false, detail: "PI stuck at '#{final_status}' after polling")
    end
  end

  def poll_payment_intent_status(payment_intent_id)
    status = nil

    POLL_MAX_ATTEMPTS.times do |attempt|
      client = Stripe::StripeClient.new(Stripe.api_key)
      response = client.raw_request(
        :get,
        "/v1/payment_intents/#{payment_intent_id}",
        opts: { api_version: STRIPE_API_VERSION }
      )
      parsed = JSON.parse(response.http_body)
      status = parsed["status"]
      puts "  Poll #{attempt + 1}/#{POLL_MAX_ATTEMPTS}: status=#{status}"

      return status if status == "succeeded"

      sleep(POLL_INTERVAL_SECONDS)
    end

    status
  end

  def fetch_transaction_receipt(tx_hash)
    uri = URI(AppConfig::Mpp::TEMPO_RPC_URL)
    request_body = {
      jsonrpc: "2.0",
      method: "eth_getTransactionReceipt",
      params: [ tx_hash ],
      id: 1
    }.to_json

    response = Net::HTTP.post(uri, request_body, "Content-Type" => "application/json")
    body = JSON.parse(response.body)

    if body["error"]
      puts "  RPC error: #{body["error"]["message"]}"
      return nil
    end

    body["result"]
  end

  TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  def parse_transfer_logs(receipt)
    logs = receipt["logs"] || []

    logs.filter_map do |log|
      topics = log["topics"] || []
      next unless topics.length >= 3
      next unless topics[0] == TRANSFER_TOPIC

      recipient_raw = topics[2].to_s.delete_prefix("0x").downcase[-40..]
      recipient = "0x#{recipient_raw}"
      amount = log["data"].to_s.delete_prefix("0x").to_i(16)

      {
        token: log["address"],
        recipient: recipient,
        amount: amount
      }
    end
  end

  def handle_stripe_error(scenario, error)
    detail = if error.message.include?("preview") || error.message.include?("version")
               "Stripe account may not be gated into #{STRIPE_API_VERSION}: #{error.message}"
    else
               "Stripe error: #{error.message}"
    end
    record(scenario, passed: false, detail: detail)
  end
end

MppIntegrationTest.new.run
