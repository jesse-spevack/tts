# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class EpisodesControllerMppTest < ActionDispatch::IntegrationTest
      TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

      setup do
        @valid_params = {
          source_type: "extension",
          title: "Test Article",
          author: "Test Author",
          description: "A test article description",
          content: "This is the full content of the article. " * 50,
          url: "https://example.com/article"
        }

        @amount_cents = AppConfig::Mpp::PRICE_CENTS
        @currency = AppConfig::Mpp::CURRENCY
        @tx_hash = "0x#{SecureRandom.hex(32)}"
        @deposit_address = "0xdeposit#{SecureRandom.hex(16)}"

        Stripe.api_key = "sk_test_fake"

        # Every 402 challenge response calls CreatesDepositAddress, which hits
        # Stripe. Stub the endpoint globally so 402 paths don't need per-test
        # wiring. Individual tests override via `valid_credential` / helpers.
        stub_stripe_deposit_address(address: @deposit_address)
      end

      # =========================================================================
      # 402 Challenge Response
      # =========================================================================

      test "returns 402 with challenge when no auth header at all" do
        post api_v1_episodes_path, params: @valid_params, as: :json

        assert_response :payment_required
        assert response.headers["WWW-Authenticate"].present?,
          "Expected WWW-Authenticate header in 402 response"
        assert_match(/Payment /, response.headers["WWW-Authenticate"])
      end

      test "402 response body includes challenge details" do
        post api_v1_episodes_path, params: @valid_params, as: :json

        assert_response :payment_required
        json = response.parsed_body
        assert json["challenge"].present?, "Expected 'challenge' key in 402 body"
        assert json["challenge"]["id"].present?
        assert json["challenge"]["amount"].present?
        assert json["challenge"]["currency"].present?
        assert json["challenge"]["methods"].present?
      end

      test "returns 402 when bearer token is present but user is non-subscriber with no credits and free tier exhausted" do
        user = users(:free_user)
        token = GeneratesApiToken.call(user: user)

        # Exhaust free tier so ChecksEpisodeCreationPermission would normally return :forbidden
        EpisodeUsage.create!(
          user: user,
          period_start: Time.current.beginning_of_month.to_date,
          episode_count: AppConfig::Tiers::FREE_MONTHLY_EPISODES
        )

        # With MppPayable active, this should return 402 (not 403) so client can pay
        post api_v1_episodes_path,
          params: @valid_params,
          headers: bearer_header(token.plain_token),
          as: :json

        assert_response :payment_required
        assert response.headers["WWW-Authenticate"].present?
      end

      # =========================================================================
      # Subscriber bypass (existing flow unchanged)
      # =========================================================================

      test "subscriber with bearer token creates Episode with 201 — no payment needed" do
        subscriber = users(:subscriber)
        token = GeneratesApiToken.call(user: subscriber)

        assert_difference "Episode.count", 1 do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: bearer_header(token.plain_token),
            as: :json
        end

        assert_response :created
      end

      test "subscriber bypass does not create Narration" do
        subscriber = users(:subscriber)
        token = GeneratesApiToken.call(user: subscriber)

        assert_no_difference "Narration.count" do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: bearer_header(token.plain_token),
            as: :json
        end
      end

      test "credit user with bearer token creates Episode with 201 — credit deducted" do
        credit_user = users(:credit_user)
        token = GeneratesApiToken.call(user: credit_user)

        assert_difference "Episode.count", 1 do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: bearer_header(token.plain_token),
            as: :json
        end

        assert_response :created
      end

      # =========================================================================
      # MPP payment with bearer token (authenticated + paid)
      # =========================================================================

      test "authenticated non-subscriber with valid Payment credential creates Episode" do
        user = users(:free_user)
        token = GeneratesApiToken.call(user: user)
        exhaust_free_tier(user)
        credential = valid_credential

        stub_tempo_rpc_success

        assert_difference "Episode.count", 1 do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: combined_auth_header(token.plain_token, credential),
            as: :json
        end

        assert_response :created
      end

      test "authenticated non-subscriber with valid Payment credential completes MppPayment linked to user" do
        user = users(:free_user)
        token = GeneratesApiToken.call(user: user)
        exhaust_free_tier(user)
        credential = valid_credential

        stub_tempo_rpc_success

        # MppPayment row is created pending by CreatesDepositAddress (inside
        # valid_credential above); the POST transitions it to completed and
        # links it to the user. No new row.
        assert_no_difference "MppPayment.count" do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: combined_auth_header(token.plain_token, credential),
            as: :json
        end

        payment = MppPayment.last
        assert_equal user.id, payment.user_id
        assert_equal "completed", payment.status
        assert_equal @tx_hash, payment.tx_hash
      end

      test "authenticated non-subscriber with valid Payment credential gets Payment-Receipt header" do
        user = users(:free_user)
        token = GeneratesApiToken.call(user: user)
        exhaust_free_tier(user)
        credential = valid_credential

        stub_tempo_rpc_success

        post api_v1_episodes_path,
          params: @valid_params,
          headers: combined_auth_header(token.plain_token, credential),
          as: :json

        assert_response :created
        assert response.headers["Payment-Receipt"].present?,
          "Expected Payment-Receipt header in response"
      end

      test "authenticated non-subscriber with valid Payment credential does not create Narration" do
        user = users(:free_user)
        token = GeneratesApiToken.call(user: user)
        exhaust_free_tier(user)
        credential = valid_credential

        stub_tempo_rpc_success

        assert_no_difference "Narration.count" do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: combined_auth_header(token.plain_token, credential),
            as: :json
        end
      end

      # =========================================================================
      # MPP payment without bearer token (anonymous + paid)
      # =========================================================================

      test "anonymous request with valid Payment credential creates Narration, not Episode" do
        credential = valid_credential

        stub_tempo_rpc_success

        assert_difference "Narration.count", 1 do
          assert_no_difference "Episode.count" do
            post api_v1_episodes_path,
              params: @valid_params,
              headers: payment_only_header(credential),
              as: :json
          end
        end

        assert_response :created
      end

      test "anonymous request with valid Payment credential completes MppPayment (no user link)" do
        credential = valid_credential

        stub_tempo_rpc_success

        # Pending row was created by valid_credential via CreatesDepositAddress;
        # the POST just transitions it to completed.
        assert_no_difference "MppPayment.count" do
          post api_v1_episodes_path,
            params: @valid_params,
            headers: payment_only_header(credential),
            as: :json
        end

        payment = MppPayment.last
        assert_nil payment.user_id, "Anonymous payment should not be linked to a user"
        assert_equal "completed", payment.status
        assert_equal @tx_hash, payment.tx_hash
      end

      test "anonymous request with valid Payment credential gets Payment-Receipt header" do
        credential = valid_credential

        stub_tempo_rpc_success

        post api_v1_episodes_path,
          params: @valid_params,
          headers: payment_only_header(credential),
          as: :json

        assert_response :created
        assert response.headers["Payment-Receipt"].present?
      end

      test "anonymous request with valid Payment credential includes narration public_id in response" do
        credential = valid_credential

        stub_tempo_rpc_success

        post api_v1_episodes_path,
          params: @valid_params,
          headers: payment_only_header(credential),
          as: :json

        assert_response :created
        json = response.parsed_body
        assert json["id"].present?, "Expected narration public_id in response body"
        assert json["id"].start_with?("nar_"), "Narration ID should start with nar_"
      end

      # =========================================================================
      # Error cases
      # =========================================================================

      test "returns 402 when Payment credential has invalid HMAC — not 401" do
        tampered_credential = build_credential_with_tampered_hmac

        post api_v1_episodes_path,
          params: @valid_params,
          headers: payment_only_header(tampered_credential),
          as: :json

        assert_response :payment_required,
          "Invalid credential should yield 402 (new challenge), not 401"
        assert response.headers["WWW-Authenticate"].present?
      end

      test "returns 402 when Payment credential is expired" do
        expired_credential = build_expired_credential

        post api_v1_episodes_path,
          params: @valid_params,
          headers: payment_only_header(expired_credential),
          as: :json

        assert_response :payment_required,
          "Expired credential should yield 402 (new challenge)"
      end

      test "two in-flight 402s: credential echoing challenge A with tx-to address B is rejected (B5 regression)" do
        # Reproduces the B5 race: two 402s in flight (client retry) create
        # two MppPayment rows with distinct deposit addresses. Under the
        # old placeholder-recipient design, a client could submit challenge
        # A's HMAC with a Transfer event that paid deposit address B, and
        # the verifier would trust the client-supplied deposit_address and
        # mark the wrong MppPayment completed. Under Option B, deposit
        # address is resolved from the DB by challenge_id (HMAC-bound) and
        # the on-chain log must match address A — the attack fails at the
        # Transfer-event verification step.

        deposit_address_a = "0xaaaa#{SecureRandom.hex(18)}"
        deposit_address_b = "0xbbbb#{SecureRandom.hex(18)}"

        # Provision two independent 402 challenges + MppPayment rows.
        stub_stripe_deposit_address(address: deposit_address_a)
        Mpp::CreatesDepositAddress.call(amount_cents: @amount_cents, currency: @currency)
        challenge_a = Mpp::GeneratesChallenge.call(
          amount_cents: @amount_cents,
          currency: @currency,
          recipient: deposit_address_a
        ).data
        MppPayment.create!(
          amount_cents: @amount_cents,
          currency: @currency,
          challenge_id: challenge_a[:id],
          deposit_address: deposit_address_a,
          stripe_payment_intent_id: "pi_a_#{SecureRandom.hex(4)}",
          status: :pending
        )

        stub_stripe_deposit_address(address: deposit_address_b)
        Mpp::CreatesDepositAddress.call(amount_cents: @amount_cents, currency: @currency)
        challenge_b = Mpp::GeneratesChallenge.call(
          amount_cents: @amount_cents,
          currency: @currency,
          recipient: deposit_address_b
        ).data
        MppPayment.create!(
          amount_cents: @amount_cents,
          currency: @currency,
          challenge_id: challenge_b[:id],
          deposit_address: deposit_address_b,
          stripe_payment_intent_id: "pi_b_#{SecureRandom.hex(4)}",
          status: :pending
        )

        # Client pays to deposit_address_b on chain, but submits a
        # credential echoing challenge_a. Payload no longer carries a
        # deposit_address — the verifier resolves it from challenge_a's
        # MppPayment row (= deposit_address_a), so the Transfer log
        # (which references deposit_address_b) won't match.
        credential_hash = {
          challenge: {
            id: challenge_a[:id],
            realm: challenge_a[:realm],
            method: challenge_a[:method],
            intent: challenge_a[:intent],
            request: challenge_a[:request],
            expires: challenge_a[:expires]
          },
          payload: {
            type: "hash",
            hash: @tx_hash
          }
        }
        credential = Base64.strict_encode64(JSON.generate(credential_hash))

        # RPC returns a Transfer event paying deposit_address_b (the other
        # challenge's address). Under Option B the verifier requires it to
        # match the stored address for challenge_a (= deposit_address_a).
        stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
          .to_return(status: 200, body: {
            jsonrpc: "2.0",
            id: 1,
            result: {
              status: "0x1",
              logs: [
                {
                  address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN,
                  topics: [
                    TRANSFER_TOPIC,
                    pad_address("0xsender"),
                    pad_address(deposit_address_b)
                  ],
                  data: amount_to_hex(@amount_cents)
                }
              ]
            }
          }.to_json)

        post api_v1_episodes_path,
          params: @valid_params,
          headers: payment_only_header(credential),
          as: :json

        assert_response :payment_required,
          "Credential referencing challenge A with on-chain payment to " \
            "address B must be rejected (B5 regression)"

        # Neither MppPayment should be marked completed.
        payment_a = MppPayment.find_by!(challenge_id: challenge_a[:id])
        payment_b = MppPayment.find_by!(challenge_id: challenge_b[:id])
        assert_equal "pending", payment_a.status
        assert_equal "pending", payment_b.status
      end

      test "returns 402 when Payment credential tx_hash fails on-chain verification" do
        credential = valid_credential

        # Stub RPC to return a reverted transaction
        stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
          .to_return(status: 200, body: {
            jsonrpc: "2.0",
            id: 1,
            result: { status: "0x0", logs: [] }
          }.to_json)

        post api_v1_episodes_path,
          params: @valid_params,
          headers: payment_only_header(credential),
          as: :json

        assert_response :payment_required,
          "Failed on-chain verification should yield 402"
      end

      # =========================================================================
      # Authorization header format: combined Bearer + Payment (RFC 9110)
      # =========================================================================

      test "parses both Bearer and Payment from comma-separated Authorization header" do
        user = users(:free_user)
        token = GeneratesApiToken.call(user: user)
        exhaust_free_tier(user)
        credential = valid_credential

        stub_tempo_rpc_success

        # Use a single Authorization header with both schemes comma-separated
        headers = {
          "Authorization" => "Bearer #{token.plain_token}, Payment #{credential}"
        }

        post api_v1_episodes_path,
          params: @valid_params,
          headers: headers,
          as: :json

        assert_response :created
        # Should create Episode (not Narration) because user is authenticated
        assert_equal user.id, Episode.last.user_id
      end

      private

      # -----------------------------------------------------------------------
      # User setup helpers
      # -----------------------------------------------------------------------

      def exhaust_free_tier(user)
        EpisodeUsage.create!(
          user: user,
          period_start: Time.current.beginning_of_month.to_date,
          episode_count: AppConfig::Tiers::FREE_MONTHLY_EPISODES
        )
      end

      # -----------------------------------------------------------------------
      # Header helpers
      # -----------------------------------------------------------------------

      def bearer_header(token)
        { "Authorization" => "Bearer #{token}" }
      end

      def payment_only_header(credential)
        { "Authorization" => "Payment #{credential}" }
      end

      def combined_auth_header(bearer_token, credential)
        { "Authorization" => "Bearer #{bearer_token}, Payment #{credential}" }
      end

      # -----------------------------------------------------------------------
      # Challenge / credential helpers
      # -----------------------------------------------------------------------

      # Simulate the production 402 flow: provision a deposit address, sign
      # a challenge with it as recipient, persist the MppPayment row. Returns
      # the challenge hash so credential builders can echo its fields.
      def provision_challenge(deposit_address: @deposit_address, expires_offset: nil)
        Mpp::CreatesDepositAddress.call(
          amount_cents: @amount_cents,
          currency: @currency
        )

        challenge = if expires_offset
          travel_to(expires_offset) do
            Mpp::GeneratesChallenge.call(
              amount_cents: @amount_cents,
              currency: @currency,
              recipient: deposit_address
            ).data
          end
        else
          Mpp::GeneratesChallenge.call(
            amount_cents: @amount_cents,
            currency: @currency,
            recipient: deposit_address
          ).data
        end

        MppPayment.create!(
          amount_cents: @amount_cents,
          currency: @currency,
          challenge_id: challenge[:id],
          deposit_address: deposit_address,
          stripe_payment_intent_id: "pi_test_#{SecureRandom.hex(8)}",
          status: :pending
        )

        challenge
      end

      def valid_credential
        challenge = provision_challenge

        credential_hash = {
          challenge: {
            id: challenge[:id],
            realm: challenge[:realm],
            method: challenge[:method],
            intent: challenge[:intent],
            request: challenge[:request],
            expires: challenge[:expires]
          },
          payload: {
            type: "hash",
            hash: @tx_hash
          }
        }

        Base64.strict_encode64(JSON.generate(credential_hash))
      end

      def build_credential_with_tampered_hmac
        challenge = provision_challenge

        credential_hash = {
          challenge: {
            id: "a" * 64, # tampered HMAC
            realm: challenge[:realm],
            method: challenge[:method],
            intent: challenge[:intent],
            request: challenge[:request],
            expires: challenge[:expires]
          },
          payload: {
            type: "hash",
            hash: @tx_hash
          }
        }

        Base64.strict_encode64(JSON.generate(credential_hash))
      end

      def build_expired_credential
        expired_challenge = provision_challenge(expires_offset: 10.minutes.ago)

        credential_hash = {
          challenge: {
            id: expired_challenge[:id],
            realm: expired_challenge[:realm],
            method: expired_challenge[:method],
            intent: expired_challenge[:intent],
            request: expired_challenge[:request],
            expires: expired_challenge[:expires]
          },
          payload: {
            type: "hash",
            hash: @tx_hash
          }
        }

        Base64.strict_encode64(JSON.generate(credential_hash))
      end

      # -----------------------------------------------------------------------
      # WebMock stubs
      # -----------------------------------------------------------------------

      def stub_tempo_rpc_success
        stub_request(:post, AppConfig::Mpp::TEMPO_RPC_URL)
          .to_return(status: 200, body: {
            jsonrpc: "2.0",
            id: 1,
            result: {
              status: "0x1",
              logs: [
                {
                  address: AppConfig::Mpp::TEMPO_CURRENCY_TOKEN,
                  topics: [
                    TRANSFER_TOPIC,
                    pad_address("0xsender"),
                    pad_address(@deposit_address)
                  ],
                  data: amount_to_hex(@amount_cents)
                }
              ]
            }
          }.to_json)
      end

      def stub_stripe_deposit_address(address:)
        stub_request(:post, "https://api.stripe.com/v1/payment_intents")
          .to_return(status: 200, body: {
            id: "pi_test_#{SecureRandom.hex(8)}",
            object: "payment_intent",
            amount: @amount_cents,
            currency: @currency,
            status: "requires_action",
            next_action: {
              type: "crypto_display_details",
              crypto_display_details: {
                deposit_addresses: {
                  tempo: { address: address }
                }
              }
            }
          }.to_json, headers: { "Content-Type" => "application/json" })
      end

      # Pad an address to 32 bytes (64 hex chars) as Ethereum log topics
      def pad_address(address)
        clean = address.delete_prefix("0x").downcase
        "0x" + clean.rjust(64, "0")
      end

      # Convert a cents value to the 32-byte hex uint256 the on-chain
      # Transfer event's `data` field carries. Matches production:
      # cents -> fiat USD -> token base units (6 decimals).
      def amount_to_hex(amount_cents)
        base_units = (amount_cents * (10**AppConfig::Mpp::TEMPO_TOKEN_DECIMALS)) / 100
        "0x" + base_units.to_s(16).rjust(64, "0")
      end
    end
  end
end
