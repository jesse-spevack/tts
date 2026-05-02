require "test_helper"

module Api
  module V1
    module Mpp
      class NarrationsControllerTest < ActionDispatch::IntegrationTest
        TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

        # === SHOW — valid prefix_id, pending narration ===

        test "show returns 200 with status and metadata for pending narration" do
          narration = narrations(:one)

          get api_v1_mpp_narration_path(narration.prefix_id), as: :json

          assert_response :ok
          json = response.parsed_body
          assert_equal narration.prefix_id, json["id"]
          assert_equal "pending", json["status"]
          assert_equal narration.title, json["title"]
          assert_equal narration.author, json["author"]
        end

        test "show does not include audio_url for pending narration" do
          narration = narrations(:one)

          get api_v1_mpp_narration_path(narration.prefix_id), as: :json

          assert_response :ok
          json = response.parsed_body
          assert_nil json["audio_url"]
        end

        test "show does not include audio_url for processing narration" do
          narration = narrations(:processing)

          get api_v1_mpp_narration_path(narration.prefix_id), as: :json

          assert_response :ok
          json = response.parsed_body
          assert_equal "processing", json["status"]
          assert_nil json["audio_url"]
        end

        # === SHOW — complete narration with audio ===

        test "show includes audio_url when narration is complete" do
          narration = narrations(:completed)
          # Stub the signed-URL generator — it talks to GCS/IAM in real life,
          # which we don't want to exercise from a controller integration test.
          # Service-level coverage lives in GeneratesNarrationAudioUrlTest.
          stubbed_url = "https://storage.googleapis.com/test/narrations/#{narration.gcs_episode_id}.mp3?X-Goog-Signature=abc"
          Mocktail.replace(GeneratesNarrationAudioUrl)
          stubs { |m| GeneratesNarrationAudioUrl.call(m.any) }.with { stubbed_url }

          get api_v1_mpp_narration_path(narration.prefix_id), as: :json

          assert_response :ok
          json = response.parsed_body
          assert_equal "complete", json["status"]
          assert json["audio_url"].present?
          assert_includes json["audio_url"], narration.gcs_episode_id
        end

        test "show includes duration_seconds when narration is complete" do
          narration = narrations(:completed)
          Mocktail.replace(GeneratesNarrationAudioUrl)
          stubs { |m| GeneratesNarrationAudioUrl.call(m.any) }.with { "https://example.com/signed.mp3" }

          get api_v1_mpp_narration_path(narration.prefix_id), as: :json

          assert_response :ok
          json = response.parsed_body
          assert_equal narration.duration_seconds, json["duration_seconds"]
        end

        # === SHOW — expired narration ===

        test "show returns 404 for expired narration" do
          narration = narrations(:expired)

          get api_v1_mpp_narration_path(narration.prefix_id), as: :json

          assert_response :not_found
        end

        # === SHOW — invalid prefix_id ===

        test "show returns 404 for nonexistent prefix_id" do
          get api_v1_mpp_narration_path("nar_does_not_exist_at_all"), as: :json

          assert_response :not_found
        end

        # === No authentication required ===

        test "show does not require bearer token" do
          narration = narrations(:one)

          get api_v1_mpp_narration_path(narration.prefix_id), as: :json

          assert_response :ok
        end

        # === Rate limiting ===

        test "rate limits narration show requests per IP" do
          narration = narrations(:one)

          # Use a fresh memory store for rate limiting
          memory_store = ActiveSupport::Cache::MemoryStore.new
          original_cache = Rack::Attack.cache.store
          Rack::Attack.cache.store = memory_store
          Rack::Attack.reset!

          freeze_time do
            # Make 60 requests (the limit)
            60.times do
              get api_v1_mpp_narration_path(narration.prefix_id), as: :json
              assert_response :ok
            end

            # The 61st request should be rate limited
            get api_v1_mpp_narration_path(narration.prefix_id), as: :json
            assert_response :too_many_requests
          end
        ensure
          unfreeze_time
          Rack::Attack.reset!
          Rack::Attack.cache.store = original_cache
        end

        # === Old location no longer routes ===

        test "old /api/v1/narrations/:id URL is no longer routed" do
          narration = narrations(:one)

          get "/api/v1/narrations/#{narration.prefix_id}", as: :json

          assert_response :not_found
        end

        # =====================================================================
        # === CREATE — anonymous MPP path (agent-team-8qa / .3b)           ===
        # =====================================================================
        #
        # These tests exercise POST /api/v1/mpp/narrations, the anonymous MPP
        # flow (no Bearer token). Three code paths:
        #
        #   1. No Payment credential  → 402 challenge, WWW-Authenticate set
        #   2. Valid Payment credential → 201 + Payment-Receipt, Narration created
        #   3. Invalid voice           → 422
        #
        # Tier-aware pricing: the resolved voice drives the challenge price
        # (Standard = 75c, Premium = 150c) via AppConfig::Mpp::PRICE_*_CENTS.

        class CreateTest < ActionDispatch::IntegrationTest
          TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

          setup do
            @valid_params = {
              title: "Test Article",
              author: "Test Author",
              description: "A test article description",
              content: "This is the full content of the article. " * 50,
              url: "https://example.com/article",
              source_type: "url"
            }

            @currency = AppConfig::Mpp::CURRENCY
            @tx_hash = "0x#{SecureRandom.hex(32)}"
            @deposit_address = "0xdeposit#{SecureRandom.hex(16)}"

            Stripe.api_key = "sk_test_fake"

            # Every 402 challenge response calls CreatesDepositAddress, which
            # hits Stripe. Stub the endpoint globally so 402 paths don't need
            # per-test wiring. Individual tests override via valid_credential.
            stub_stripe_deposit_address(address: @deposit_address)
          end

          # -------------------------------------------------------------------
          # 402 Challenge — no Payment credential
          # -------------------------------------------------------------------

          test "POST without Payment header returns 402 with WWW-Authenticate" do
            post api_v1_mpp_narrations_path, params: @valid_params, as: :json

            assert_response :payment_required
            assert response.headers["WWW-Authenticate"].present?,
              "Expected WWW-Authenticate header in 402 response"
            assert_match(/\APayment /, response.headers["WWW-Authenticate"])
          end

          test "POST without Payment header returns challenge body with id/amount/currency/methods" do
            post api_v1_mpp_narrations_path, params: @valid_params, as: :json

            assert_response :payment_required
            json = response.parsed_body
            assert json["challenge"].present?, "Expected 'challenge' key in 402 body"
            assert json["challenge"]["id"].present?
            assert json["challenge"]["amount"].present?
            assert json["challenge"]["currency"].present?
            assert json["challenge"]["methods"].present?
          end

          # -------------------------------------------------------------------
          # 402 Challenge — parallel tempo + stripe methods (agent-team-k71e.1)
          # -------------------------------------------------------------------

          test "402 advertises both method=tempo and method=stripe in WWW-Authenticate" do
            post api_v1_mpp_narrations_path, params: @valid_params, as: :json

            assert_response :payment_required
            header = response.headers["WWW-Authenticate"]
            assert header.present?
            assert_includes header, 'method="tempo"'
            assert_includes header, 'method="stripe"'
          end

          test "402 WWW-Authenticate splits to exactly 2 challenges via the mppx /Payment\\s+/i regex" do
            # AC #3: parses correctly per RFC 9110 multi-challenge grammar.
            # mppx 0.6.13's Challenge.deserializeList uses /Payment\s+/gi to
            # split a comma-joined header into per-method challenges. Mirror
            # that here so the test reflects what link-cli actually does.
            post api_v1_mpp_narrations_path, params: @valid_params, as: :json

            assert_response :payment_required
            header = response.headers["WWW-Authenticate"]

            challenges = header.split(/Payment\s+/i).reject(&:empty?)
            assert_equal 2, challenges.size,
              "Expected exactly 2 Payment challenges, got #{challenges.size}: #{header.inspect}"
          end

          test "402 body methods array advertises both tempo and stripe" do
            post api_v1_mpp_narrations_path, params: @valid_params, as: :json

            assert_response :payment_required
            json = response.parsed_body
            assert_equal [ "tempo", "stripe" ], json["challenge"]["methods"]
          end

          test "POST without Payment header, voice=felix (Standard) returns 402 with price 75" do
            post api_v1_mpp_narrations_path,
              params: @valid_params.merge(voice: "felix"),
              as: :json

            assert_response :payment_required
            json = response.parsed_body
            assert_equal AppConfig::Mpp::PRICE_STANDARD_CENTS, json["challenge"]["amount"]
            assert_equal 75, json["challenge"]["amount"]
          end

          test "POST without Payment header, voice=callum (Premium) returns 402 with price 150" do
            post api_v1_mpp_narrations_path,
              params: @valid_params.merge(voice: "callum"),
              as: :json

            assert_response :payment_required
            json = response.parsed_body
            assert_equal AppConfig::Mpp::PRICE_PREMIUM_CENTS, json["challenge"]["amount"]
            assert_equal 150, json["challenge"]["amount"]
          end

          test "POST without Payment header and no voice param defaults to Voice::DEFAULT_KEY (felix/Standard/75)" do
            # DEFAULT_KEY is 'felix', which is Standard tier → 75c
            assert_equal "felix", Voice::DEFAULT_KEY
            assert_equal :standard, Voice.find(Voice::DEFAULT_KEY).tier

            post api_v1_mpp_narrations_path, params: @valid_params, as: :json

            assert_response :payment_required
            json = response.parsed_body
            assert_equal AppConfig::Mpp::PRICE_STANDARD_CENTS, json["challenge"]["amount"]
            assert_equal 75, json["challenge"]["amount"]
          end

          # -------------------------------------------------------------------
          # 422 — invalid voice
          # -------------------------------------------------------------------

          test "POST with invalid voice (with or without Payment header) returns 422" do
            post api_v1_mpp_narrations_path,
              params: @valid_params.merge(voice: "nonexistent_voice"),
              as: :json

            assert_response :unprocessable_entity
            # No WWW-Authenticate — this isn't a payment issue, it's a bad param
            assert_nil response.headers["WWW-Authenticate"]
          end

          # -------------------------------------------------------------------
          # 201 — valid Payment credential creates Narration
          # -------------------------------------------------------------------

          test "POST with valid Payment credential (voice=felix) creates Narration and returns 201" do
            credential = valid_credential(voice_tier: :standard, amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            assert_difference "Narration.count", 1 do
              post api_v1_mpp_narrations_path,
                params: @valid_params.merge(voice: "felix"),
                headers: payment_only_header(credential),
                as: :json
            end

            assert_response :created
            narration = Narration.last
            # felix → en-GB-Standard-D
            assert_equal "en-GB-Standard-D", narration.voice
          end

          test "POST with valid Payment credential and NO voice param creates Standard-voice Narration" do
            # Regression test for default-voice pricing arbitrage: without an
            # explicit voice param, the controller resolves to Voice::DEFAULT_KEY
            # ("felix", Standard tier, 75c) and must synthesize with felix's
            # Google voice — NOT the Premium DEFAULT_CHIRP fallback inside
            # Voice.google_voice_for. Paying Standard price for Premium
            # synthesis would be an undetectable arbitrage.
            credential = valid_credential(voice_tier: :standard, amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            assert_difference "Narration.count", 1 do
              post api_v1_mpp_narrations_path,
                params: @valid_params, # no :voice key
                headers: payment_only_header(credential),
                as: :json
            end

            assert_response :created
            narration = Narration.last
            # felix (DEFAULT_KEY, Standard) → en-GB-Standard-D
            assert_equal "en-GB-Standard-D", narration.voice,
              "Default-voice narration must synthesize with Standard voice, not Premium Chirp3-HD"
          end

          test "POST with valid Payment credential sets Payment-Receipt header" do
            credential = valid_credential(voice_tier: :standard, amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            post api_v1_mpp_narrations_path,
              params: @valid_params.merge(voice: "felix"),
              headers: payment_only_header(credential),
              as: :json

            assert_response :created
            assert response.headers["Payment-Receipt"].present?,
              "Expected Payment-Receipt header in 201 response"
          end

          test "POST with valid Payment credential returns Narration JSON with prefix_id" do
            credential = valid_credential(voice_tier: :standard, amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            post api_v1_mpp_narrations_path,
              params: @valid_params.merge(voice: "felix"),
              headers: payment_only_header(credential),
              as: :json

            assert_response :created
            json = response.parsed_body
            assert json["id"].present?, "Expected narration prefix_id in response body"
            assert json["id"].start_with?("nar_"), "Narration id should start with nar_"
          end

          test "POST with valid Payment credential (voice=callum) creates Premium-voice Narration at 150c" do
            credential = valid_credential(voice_tier: :premium, amount_cents: AppConfig::Mpp::PRICE_PREMIUM_CENTS)
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_PREMIUM_CENTS)

            assert_difference "Narration.count", 1 do
              post api_v1_mpp_narrations_path,
                params: @valid_params.merge(voice: "callum"),
                headers: payment_only_header(credential),
                as: :json
            end

            assert_response :created
            narration = Narration.last
            # callum → en-GB-Chirp3-HD-Enceladus
            assert_equal "en-GB-Chirp3-HD-Enceladus", narration.voice
            assert response.headers["Payment-Receipt"].present?
          end

          test "POST with valid credential transitions MppPayment pending → completed (no user link)" do
            credential = valid_credential(voice_tier: :standard, amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            # Pending row already created by valid_credential (via ProvisionsChallenge);
            # POST transitions it to completed. No new row.
            assert_no_difference "MppPayment.count" do
              post api_v1_mpp_narrations_path,
                params: @valid_params.merge(voice: "felix"),
                headers: payment_only_header(credential),
                as: :json
            end

            assert_response :created
            payment = MppPayment.last
            assert_nil payment.user_id, "Anonymous payment must not be linked to a user"
            assert_equal "completed", payment.status
            assert_equal @tx_hash, payment.tx_hash
          end

          # -------------------------------------------------------------------
          # 402 re-challenge — credential/price mismatch and malformed inputs
          # -------------------------------------------------------------------

          test "POST with credential paid for Standard but requesting Premium voice → 402 re-challenge" do
            # Attacker buys a cheap Standard challenge then tries to claim a
            # Premium voice. voice_tier is embedded in the HMAC-signed request
            # blob so either HMAC fails OR the tier stored in the credential
            # won't match the request voice — either way we re-issue 402.
            credential = valid_credential(voice_tier: :standard, amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            post api_v1_mpp_narrations_path,
              params: @valid_params.merge(voice: "callum"),
              headers: payment_only_header(credential),
              as: :json

            assert_response :payment_required,
              "Standard-priced credential must not satisfy a Premium voice request"
            assert response.headers["WWW-Authenticate"].present?
          end

          test "POST with malformed Payment header returns 402 re-challenge" do
            post api_v1_mpp_narrations_path,
              params: @valid_params,
              headers: payment_only_header("this_is_not_valid_base64_or_json"),
              as: :json

            assert_response :payment_required,
              "Malformed credential should yield 402 (new challenge), not 400/500"
            assert response.headers["WWW-Authenticate"].present?
          end

          test "POST with tampered HMAC in Payment credential returns 402 re-challenge" do
            tampered = build_credential_with_tampered_hmac

            post api_v1_mpp_narrations_path,
              params: @valid_params,
              headers: payment_only_header(tampered),
              as: :json

            assert_response :payment_required,
              "Invalid credential should yield 402 (new challenge), not 401"
            assert response.headers["WWW-Authenticate"].present?
          end

          test "POST with expired Payment credential returns 402 re-challenge" do
            expired = build_expired_credential

            post api_v1_mpp_narrations_path,
              params: @valid_params,
              headers: payment_only_header(expired),
              as: :json

            assert_response :payment_required,
              "Expired credential should yield 402 (new challenge)"
          end

          private

          def payment_only_header(credential)
            { "Authorization" => "Payment #{credential}" }
          end

          # Simulate the production 402 flow: provision a deposit address, sign
          # a challenge with it as recipient, persist the MppPayment row.
          # Returns the challenge hash so credential builders can echo fields.
          def provision_challenge(voice_tier:, amount_cents:, deposit_address: @deposit_address, expires_offset: nil)
            ::Mpp::CreatesDepositAddress.call(
              amount_cents: amount_cents,
              currency: @currency
            )

            challenge = if expires_offset
              travel_to(expires_offset) do
                ::Mpp::GeneratesChallenge.call(
                  amount_cents: amount_cents,
                  currency: @currency,
                  recipient: deposit_address,
                  voice_tier: voice_tier
                ).data
              end
            else
              ::Mpp::GeneratesChallenge.call(
                amount_cents: amount_cents,
                currency: @currency,
                recipient: deposit_address,
                voice_tier: voice_tier
              ).data
            end

            MppPayment.create!(
              amount_cents: amount_cents,
              currency: @currency,
              challenge_id: challenge[:id],
              deposit_address: deposit_address,
              stripe_payment_intent_id: "pi_test_#{SecureRandom.hex(8)}",
              status: :pending
            )

            challenge
          end

          def valid_credential(voice_tier:, amount_cents:)
            challenge = provision_challenge(voice_tier: voice_tier, amount_cents: amount_cents)

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
            challenge = provision_challenge(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )

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
            expired_challenge = provision_challenge(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS,
              expires_offset: 10.minutes.ago
            )

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

          def stub_tempo_rpc_success(amount_cents:)
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
                      data: amount_to_hex(amount_cents)
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
                amount: AppConfig::Mpp::PRICE_PREMIUM_CENTS,
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

          def pad_address(address)
            clean = address.delete_prefix("0x").downcase
            "0x" + clean.rjust(64, "0")
          end

          def amount_to_hex(amount_cents)
            base_units = (amount_cents * (10**AppConfig::Mpp::TEMPO_TOKEN_DECIMALS)) / 100
            "0x" + base_units.to_s(16).rjust(64, "0")
          end
        end

        # =====================================================================
        # === CREATE — anonymous MPP SPT path (agent-team-k71e.2)           ===
        # =====================================================================
        #
        # These tests exercise POST /api/v1/mpp/narrations from the
        # perspective of a Stripe Link wallet client (e.g. @stripe/link-cli).
        # The flow:
        #
        #   1. POST without credential  → 402 with WWW-Authenticate carrying
        #      both tempo and stripe Payment-scheme challenges (k71e.1 — live).
        #   2. Client splits the header on /Payment\s+/i, picks the
        #      method="stripe" challenge.
        #   3. Client builds an SPT credential — base64url-no-padding of
        #      JSON {challenge: <stripe_challenge>, payload: {spt: "spt_..."}}
        #      — and retries with `Authorization: Payment <encoded>`.
        #   4. Server verifies the SPT via Stripe::PaymentIntent.create with
        #      shared_payment_granted_token + idempotency_key (k71e.5 — not
        #      yet shipped). On success, returns 201 + Payment-Receipt.
        #   5. On replay (Stripe returns idempotent-replayed: true), server
        #      returns 402 with a fresh challenge.
        #
        # These tests are TDD red-phase: they MUST fail on current main
        # because Mpp::VerifiesCredential rejects credentials whose
        # payload lacks {hash} or {signature}. They will pass once
        # k71e.4 (dispatcher) + k71e.5 (SPT verifier) ship.
        #
        # Stripe API is stubbed via WebMock. The deposit-address stub
        # (existing) handles the 402 challenge step; the SPT-redemption
        # stub (new) handles the verify-time PaymentIntent.create call.
        # The two are differentiated by request-body content:
        # shared_payment_granted_token is present on the SPT call only.

        class CreateSptTest < ActionDispatch::IntegrationTest
          setup do
            @valid_params = {
              title: "Test Article",
              author: "Test Author",
              description: "A test article description",
              content: "This is the full content of the article. " * 50,
              url: "https://example.com/article",
              source_type: "url"
            }

            @currency = AppConfig::Mpp::CURRENCY
            @deposit_address = "0xdeposit#{SecureRandom.hex(16)}"
            @spt = "spt_test_#{SecureRandom.hex(16)}"
            @stripe_pi_id = "pi_test_#{SecureRandom.hex(8)}"

            Stripe.api_key = "sk_test_fake"

            # Provisioning a 402 challenge calls CreatesDepositAddress for
            # the tempo-method side. Stub the deposit-address PI creation
            # so 402 issuance works regardless of test scenario. The
            # SPT-redemption stub below targets a DIFFERENT body shape
            # (shared_payment_granted_token), so the two stubs do not
            # conflict — WebMock matches by body keys.
            stub_stripe_deposit_address(address: @deposit_address)
          end

          # -------------------------------------------------------------------
          # Happy path — link-cli-style anonymous SPT redemption
          # -------------------------------------------------------------------

          test "POST with SPT credential (method=stripe) creates Narration and returns 201" do
            stripe_challenge = trigger_402_and_pick_stripe_challenge
            credential = build_spt_credential(stripe_challenge: stripe_challenge, spt: @spt)
            stub_stripe_spt_redemption_success(spt: @spt, payment_intent_id: @stripe_pi_id)

            assert_difference "Narration.count", 1 do
              post api_v1_mpp_narrations_path,
                params: @valid_params.merge(voice: "felix"),
                headers: payment_only_header(credential),
                as: :json
            end

            assert_response :created,
              "SPT credential should yield 201 once k71e.4 + k71e.5 ship — " \
              "currently fails because VerifiesCredential rejects {spt} payload."
          end

          test "POST with SPT credential sets Payment-Receipt header" do
            stripe_challenge = trigger_402_and_pick_stripe_challenge
            credential = build_spt_credential(stripe_challenge: stripe_challenge, spt: @spt)
            stub_stripe_spt_redemption_success(spt: @spt, payment_intent_id: @stripe_pi_id)

            post api_v1_mpp_narrations_path,
              params: @valid_params.merge(voice: "felix"),
              headers: payment_only_header(credential),
              as: :json

            assert_response :created
            assert response.headers["Payment-Receipt"].present?,
              "SPT-redeemed response must carry Payment-Receipt header"
          end

          test "POST with SPT credential returns Narration JSON with nar_-prefixed id" do
            stripe_challenge = trigger_402_and_pick_stripe_challenge
            credential = build_spt_credential(stripe_challenge: stripe_challenge, spt: @spt)
            stub_stripe_spt_redemption_success(spt: @spt, payment_intent_id: @stripe_pi_id)

            post api_v1_mpp_narrations_path,
              params: @valid_params.merge(voice: "felix"),
              headers: payment_only_header(credential),
              as: :json

            assert_response :created
            json = response.parsed_body
            assert json["id"].present?,
              "SPT-redeemed Narration must have an id in the response body"
            assert json["id"].start_with?("nar_"),
              "Narration id should start with nar_ (got #{json["id"].inspect})"
          end

          # -------------------------------------------------------------------
          # Idempotent replay — Stripe returns idempotent-replayed: true
          # -------------------------------------------------------------------
          #
          # Per agent-team-p6wb spike (failure taxonomy #1): if Stripe
          # returns the `idempotent-replayed: true` response header, the
          # SPT has already been redeemed. The merchant must treat this
          # as a permanent failure for that SPT and re-issue a fresh
          # 402 challenge so the client can mint a new SPT.

          test "POST with already-redeemed SPT (idempotent-replayed: true) returns 402 with new challenge" do
            stripe_challenge = trigger_402_and_pick_stripe_challenge
            credential = build_spt_credential(stripe_challenge: stripe_challenge, spt: @spt)
            spt_stub = stub_stripe_spt_redemption_replay(spt: @spt, payment_intent_id: @stripe_pi_id)

            assert_no_difference "Narration.count" do
              post api_v1_mpp_narrations_path,
                params: @valid_params.merge(voice: "felix"),
                headers: payment_only_header(credential),
                as: :json
            end

            # Once k71e.5's verifier ships, the SPT-redemption stub MUST be
            # invoked — that's the whole point of the replay path. A test
            # that only asserts the eventual 402 would falsely pass on
            # current main (where the verifier rejects the credential
            # without ever calling Stripe). Asserting the stub was hit
            # also pins the contract: the verifier must hit Stripe with
            # the SPT before deciding replay vs fresh.
            assert_requested(spt_stub, at_least_times: 1)

            assert_response :payment_required,
              "Replayed SPT must yield 402 (not 201) — Stripe's idempotent-replayed " \
              "header marks this SPT as already-spent."
            assert response.headers["WWW-Authenticate"].present?,
              "Replay 402 must advertise a fresh challenge so the client can re-mint."
          end

          private

          def payment_only_header(credential)
            { "Authorization" => "Payment #{credential}" }
          end

          # POST without credential to drive the real 402 → ProvisionsChallenge
          # flow (creates MppPayment rows, signs HMAC challenges, sets
          # WWW-Authenticate). Returns the parsed stripe-method challenge
          # hash extracted from the WWW-Authenticate header — the same
          # object an SPT client would build its credential from.
          def trigger_402_and_pick_stripe_challenge
            post api_v1_mpp_narrations_path,
              params: @valid_params.merge(voice: "felix"),
              as: :json
            assert_response :payment_required,
              "Setup precondition: 402 from no-credential POST"

            header = response.headers["WWW-Authenticate"]
            assert header.present?, "Setup precondition: WWW-Authenticate present on 402"

            challenges = parse_payment_challenges(header)
            stripe = challenges.find { |c| c[:method] == "stripe" }
            assert stripe, "Setup precondition: stripe-method challenge advertised in WWW-Authenticate"
            stripe
          end

          # Parse a comma-joined `WWW-Authenticate: Payment ..., Payment ...`
          # header into individual challenge hashes. Mirrors mppx 0.6.13's
          # Challenge.deserializeList: split on /Payment\s+/gi, drop empties,
          # then key=value-pair-parse each entry.
          def parse_payment_challenges(header)
            header.split(/Payment\s+/i).reject(&:empty?).map do |entry|
              fields = {}
              entry.scan(/(\w+)="([^"]*)"/) { |k, v| fields[k.to_sym] = v }
              fields
            end
          end

          # Match mppx Credential.serialize: base64url-encoded JSON of
          # {challenge, payload}, NO padding. The challenge is the parsed
          # stripe-method entry from the WWW-Authenticate header (id, realm,
          # method, intent, request, expires); the payload carries the SPT.
          def build_spt_credential(stripe_challenge:, spt:)
            credential_hash = {
              challenge: {
                id: stripe_challenge[:id],
                realm: stripe_challenge[:realm],
                method: stripe_challenge[:method],
                intent: stripe_challenge[:intent],
                request: stripe_challenge[:request],
                expires: stripe_challenge[:expires]
              },
              payload: {
                spt: spt
              }
            }

            Base64.urlsafe_encode64(JSON.generate(credential_hash), padding: false)
          end

          # The deposit-address stub (issued at challenge time). Mirrors
          # CreateTest#stub_stripe_deposit_address byte-for-byte so the
          # 402-issuance side of the flow works identically.
          def stub_stripe_deposit_address(address:)
            stub_request(:post, "https://api.stripe.com/v1/payment_intents")
              .with { |req| !req.body.to_s.include?("shared_payment_granted_token") }
              .to_return(status: 200, body: {
                id: "pi_test_#{SecureRandom.hex(8)}",
                object: "payment_intent",
                amount: AppConfig::Mpp::PRICE_PREMIUM_CENTS,
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

          # Stub the SPT-redemption call k71e.5's verifier will make:
          # POST /v1/payment_intents with shared_payment_granted_token in
          # the body, returns a succeeded PaymentIntent. Match on the
          # presence of `shared_payment_granted_token` so this stub does
          # not collide with the deposit-address stub.
          def stub_stripe_spt_redemption_success(spt:, payment_intent_id:)
            stub_request(:post, "https://api.stripe.com/v1/payment_intents")
              .with { |req| req.body.to_s.include?("shared_payment_granted_token") &&
                            req.body.to_s.include?(spt) }
              .to_return(
                status: 200,
                body: {
                  id: payment_intent_id,
                  object: "payment_intent",
                  amount: AppConfig::Mpp::PRICE_STANDARD_CENTS,
                  currency: @currency,
                  status: "succeeded"
                }.to_json,
                headers: { "Content-Type" => "application/json" }
              )
          end

          # Same as above but signals replay via the idempotent-replayed
          # response header. Per spike: Stripe still returns the original
          # PaymentIntent object on a replayed idempotency_key; the
          # `idempotent-replayed: true` response header is the only
          # discriminator between fresh and replayed redemptions.
          def stub_stripe_spt_redemption_replay(spt:, payment_intent_id:)
            stub_request(:post, "https://api.stripe.com/v1/payment_intents")
              .with { |req| req.body.to_s.include?("shared_payment_granted_token") &&
                            req.body.to_s.include?(spt) }
              .to_return(
                status: 200,
                body: {
                  id: payment_intent_id,
                  object: "payment_intent",
                  amount: AppConfig::Mpp::PRICE_STANDARD_CENTS,
                  currency: @currency,
                  status: "succeeded"
                }.to_json,
                headers: {
                  "Content-Type" => "application/json",
                  "idempotent-replayed" => "true"
                }
              )
          end
        end
      end
    end
  end
end
