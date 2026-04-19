require "test_helper"

module Api
  module V1
    module Mpp
      class EpisodesControllerTest < ActionDispatch::IntegrationTest
        # Skeleton-level coverage for .3a (foundation commit). The actual
        # MPP challenge flow for this controller lands in .3c — see
        # agent-team-392.

        test "controller class exists and inherits Api::V1::BaseController" do
          assert defined?(::Api::V1::Mpp::EpisodesController),
            "Expected Api::V1::Mpp::EpisodesController to be defined"
          assert_operator ::Api::V1::Mpp::EpisodesController, :<, ::Api::V1::BaseController
        end

        test "POST /api/v1/mpp/episodes routes to Mpp::EpisodesController#create" do
          post api_v1_mpp_episodes_path, as: :json

          # Routing must succeed — any non-404 (even 401/402/422/500) is acceptable
          # for this skeleton-level check. The full MPP challenge flow lands in .3c.
          assert_not_equal 404, response.status,
            "Expected POST /api/v1/mpp/episodes to route (got 404 — route missing)"
        end

        # =====================================================================
        # === CREATE — authenticated MPP path (agent-team-392 / .3c)       ===
        # =====================================================================
        #
        # These tests exercise POST /api/v1/mpp/episodes — the authenticated
        # MPP path. Mirror of the anonymous Narration flow in
        # Api::V1::Mpp::NarrationsController#create, but:
        #
        #   1. Bearer required (401 without it)
        #   2. Creates an Episode (not a Narration) attached to the user's
        #      default podcast via GetsDefaultPodcastForUser
        #   3. MppPayment links to the user after completion
        #
        # Tier-aware pricing via ResolvesVoice: the resolved voice drives the
        # challenge price (Standard = 75c, Premium = 100c) via
        # AppConfig::Mpp::PRICE_*_CENTS.

        class CreateTest < ActionDispatch::IntegrationTest
          TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

          setup do
            @valid_params = {
              title: "Test Article",
              author: "Test Author",
              description: "A test article description",
              content: "This is the full content of the article. " * 50,
              url: "https://example.com/article",
              source_type: "extension"
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
          # 401 — Bearer required
          # -------------------------------------------------------------------

          test "POST without any Authorization header returns 401" do
            post api_v1_mpp_episodes_path, params: @valid_params, as: :json

            assert_response :unauthorized,
              "Expected 401 when no Bearer token — /mpp/episodes is authenticated-only"
          end

          test "POST with only Payment header (no Bearer) returns 401" do
            # /mpp/episodes is the AUTHENTICATED MPP path. A Payment-only
            # request belongs on /mpp/narrations instead.
            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )

            post api_v1_mpp_episodes_path,
              params: @valid_params,
              headers: payment_only_header(credential),
              as: :json

            assert_response :unauthorized,
              "Payment-only caller must hit /mpp/narrations, not /mpp/episodes"
          end

          test "POST with invalid Bearer token returns 401" do
            post api_v1_mpp_episodes_path,
              params: @valid_params,
              headers: bearer_header("sk_live_totally_bogus_token_value"),
              as: :json

            assert_response :unauthorized
          end

          # -------------------------------------------------------------------
          # 402 Challenge — Bearer valid, no Payment credential
          # -------------------------------------------------------------------

          test "Bearer valid, no Payment header, voice=felix (Standard) returns 402 at 75c" do
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)

            post api_v1_mpp_episodes_path,
              params: @valid_params.merge(voice: "felix"),
              headers: bearer_header(token.plain_token),
              as: :json

            assert_response :payment_required
            assert response.headers["WWW-Authenticate"].present?,
              "Expected WWW-Authenticate header in 402 response"
            assert_match(/\APayment /, response.headers["WWW-Authenticate"])

            json = response.parsed_body
            assert_equal AppConfig::Mpp::PRICE_STANDARD_CENTS, json["challenge"]["amount"]
            assert_equal 75, json["challenge"]["amount"]
          end

          test "Bearer valid, no Payment header, voice=callum (Premium) returns 402 at 100c" do
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)

            post api_v1_mpp_episodes_path,
              params: @valid_params.merge(voice: "callum"),
              headers: bearer_header(token.plain_token),
              as: :json

            assert_response :payment_required
            json = response.parsed_body
            assert_equal AppConfig::Mpp::PRICE_PREMIUM_CENTS, json["challenge"]["amount"]
            assert_equal 100, json["challenge"]["amount"]
          end

          test "Bearer valid, no Payment header, no voice param defaults to Voice::DEFAULT_KEY (felix/Standard/75)" do
            # DEFAULT_KEY is 'felix', Standard tier → 75c. No voice_preference
            # on the user means ResolvesVoice falls through to DEFAULT_KEY.
            assert_equal "felix", Voice::DEFAULT_KEY
            assert_equal :standard, Voice.find(Voice::DEFAULT_KEY).tier

            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)

            post api_v1_mpp_episodes_path,
              params: @valid_params, # no :voice key
              headers: bearer_header(token.plain_token),
              as: :json

            assert_response :payment_required
            json = response.parsed_body
            assert_equal AppConfig::Mpp::PRICE_STANDARD_CENTS, json["challenge"]["amount"]
            assert_equal 75, json["challenge"]["amount"]
          end

          test "402 response body includes challenge details" do
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)

            post api_v1_mpp_episodes_path,
              params: @valid_params,
              headers: bearer_header(token.plain_token),
              as: :json

            assert_response :payment_required
            json = response.parsed_body
            assert json["challenge"].present?, "Expected 'challenge' key in 402 body"
            assert json["challenge"]["id"].present?
            assert json["challenge"]["amount"].present?
            assert json["challenge"]["currency"].present?
            assert json["challenge"]["methods"].present?
          end

          # -------------------------------------------------------------------
          # 422 — invalid voice (checked BEFORE credential)
          # -------------------------------------------------------------------

          test "Bearer valid, voice=nonexistent returns 422 (no Payment header)" do
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)

            post api_v1_mpp_episodes_path,
              params: @valid_params.merge(voice: "nonexistent_voice"),
              headers: bearer_header(token.plain_token),
              as: :json

            assert_response :unprocessable_entity
            # No WWW-Authenticate — this isn't a payment issue, it's a bad param
            assert_nil response.headers["WWW-Authenticate"]
          end

          test "Bearer valid, voice=nonexistent + valid Payment header still returns 422 (not credential retry loop)" do
            # Regression: a client holding a valid credential but sending a bad
            # voice must NOT loop on 402. Voice resolution happens before the
            # credential check.
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )

            post api_v1_mpp_episodes_path,
              params: @valid_params.merge(voice: "nonexistent_voice"),
              headers: combined_auth_header(token.plain_token, credential),
              as: :json

            assert_response :unprocessable_entity
          end

          # -------------------------------------------------------------------
          # 201 — valid Bearer + valid Payment credential creates Episode
          # -------------------------------------------------------------------

          test "Bearer + valid Payment (voice=felix) creates Standard-voice Episode and returns 201" do
            # Option A (sidecar voice): Episode#voice stays delegated to User.
            # The MPP-resolved voice is propagated via job args — the processing
            # job receives voice_override, which flows to GeneratesEpisodeAudio.
            # For source_type="extension", CreatesExtensionEpisode enqueues
            # ProcessesFileEpisodeJob, so we assert voice_override there.
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            assert_difference "Episode.count", 1 do
              post api_v1_mpp_episodes_path,
                params: @valid_params.merge(voice: "felix"),
                headers: combined_auth_header(token.plain_token, credential),
                as: :json
            end

            assert_response :created
            assert_equal "en-GB-Standard-D", enqueued_voice_override,
              "voice_override on ProcessesFileEpisodeJob must be the Standard google voice for felix"
          end

          test "Bearer + valid Payment (voice=callum) creates Premium-voice Episode and returns 201" do
            # Option A: the paid-for Premium voice flows via voice_override on
            # the processing job, NOT via Episode#voice (which still delegates
            # to User#voice — free_user here is not premium, so Episode#voice
            # would be Standard). Assertion target is the job arg.
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            credential = valid_credential(
              voice_tier: :premium,
              amount_cents: AppConfig::Mpp::PRICE_PREMIUM_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_PREMIUM_CENTS)

            assert_difference "Episode.count", 1 do
              post api_v1_mpp_episodes_path,
                params: @valid_params.merge(voice: "callum"),
                headers: combined_auth_header(token.plain_token, credential),
                as: :json
            end

            assert_response :created
            # callum → en-GB-Chirp3-HD-Enceladus
            assert_equal "en-GB-Chirp3-HD-Enceladus", enqueued_voice_override,
              "voice_override on ProcessesFileEpisodeJob must be the Premium google voice for callum"
            assert response.headers["Payment-Receipt"].present?
          end

          test "Bearer + valid Payment + NO voice param creates Standard-voice Episode (regression: pricing arbitrage)" do
            # CRITICAL regression test for default-voice pricing arbitrage
            # (.3b-style bug). Without an explicit :voice param, ResolvesVoice
            # lands on Voice::DEFAULT_KEY ("felix", Standard, 75c). The
            # controller MUST forward the resolved google voice into job args
            # so synthesis uses en-GB-Standard-D (NOT the Premium DEFAULT_CHIRP
            # fallback inside Voice.google_voice_for when :is_premium leaks in).
            #
            # Under Option A, the arbitrage surface is voice_override on the
            # processing job — this is THE assertion that proves the caller
            # got what they paid for.
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            assert_difference "Episode.count", 1 do
              post api_v1_mpp_episodes_path,
                params: @valid_params, # no :voice key
                headers: combined_auth_header(token.plain_token, credential),
                as: :json
            end

            assert_response :created
            assert_equal "en-GB-Standard-D", enqueued_voice_override,
              "Default-voice Episode must synthesize with Standard voice (en-GB-Standard-D), " \
                "not Premium Chirp3-HD — pricing arbitrage regression"
          end

          test "Bearer + valid Payment sets Payment-Receipt header" do
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            post api_v1_mpp_episodes_path,
              params: @valid_params.merge(voice: "felix"),
              headers: combined_auth_header(token.plain_token, credential),
              as: :json

            assert_response :created
            assert response.headers["Payment-Receipt"].present?,
              "Expected Payment-Receipt header in 201 response"
          end

          test "Bearer + valid Payment returns Episode JSON with ep_ prefix_id" do
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            post api_v1_mpp_episodes_path,
              params: @valid_params.merge(voice: "felix"),
              headers: combined_auth_header(token.plain_token, credential),
              as: :json

            assert_response :created
            json = response.parsed_body
            assert json["id"].present?, "Expected episode prefix_id in response body"
            assert json["id"].start_with?("ep_"), "Episode id should start with ep_"
          end

          test "Bearer + valid Payment transitions MppPayment pending → completed AND links to user" do
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            # Pending row already created by valid_credential (via
            # ProvisionsChallenge); POST transitions to completed AND
            # attaches the user (distinction from anonymous path).
            assert_no_difference "MppPayment.count" do
              post api_v1_mpp_episodes_path,
                params: @valid_params.merge(voice: "felix"),
                headers: combined_auth_header(token.plain_token, credential),
                as: :json
            end

            assert_response :created
            payment = MppPayment.last
            assert_equal user.id, payment.user_id,
              "Authenticated MPP payment must be linked to current_user"
            assert_equal "completed", payment.status
            assert_equal @tx_hash, payment.tx_hash
          end

          test "Bearer + valid Payment does not create a Narration (Episode only)" do
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            assert_no_difference "Narration.count" do
              post api_v1_mpp_episodes_path,
                params: @valid_params.merge(voice: "felix"),
                headers: combined_auth_header(token.plain_token, credential),
                as: :json
            end
          end

          # -------------------------------------------------------------------
          # 402 re-challenge — credential/price mismatch and malformed inputs
          # -------------------------------------------------------------------

          test "Bearer + Standard-tier credential + voice=callum → 402 re-challenge at 100c" do
            # Attacker holds a Standard-priced credential (75c) but requests
            # a Premium voice (100c). voice_tier is embedded in the HMAC-signed
            # request blob, so the credential's tier won't match the request
            # voice's tier — re-issue 402.
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            post api_v1_mpp_episodes_path,
              params: @valid_params.merge(voice: "callum"),
              headers: combined_auth_header(token.plain_token, credential),
              as: :json

            assert_response :payment_required,
              "Standard-priced credential must not satisfy a Premium voice request"
            assert response.headers["WWW-Authenticate"].present?
            json = response.parsed_body
            assert_equal AppConfig::Mpp::PRICE_PREMIUM_CENTS, json["challenge"]["amount"],
              "Re-challenge must be at the requested voice's Premium price"
          end

          test "Bearer + malformed Payment header returns 402 re-challenge" do
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)

            post api_v1_mpp_episodes_path,
              params: @valid_params,
              headers: combined_auth_header(token.plain_token, "this_is_not_valid_base64_or_json"),
              as: :json

            assert_response :payment_required,
              "Malformed credential should yield 402 (new challenge), not 400/500"
            assert response.headers["WWW-Authenticate"].present?
          end

          test "Bearer + tampered HMAC in Payment credential returns 402 re-challenge" do
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            tampered = build_credential_with_tampered_hmac

            post api_v1_mpp_episodes_path,
              params: @valid_params,
              headers: combined_auth_header(token.plain_token, tampered),
              as: :json

            assert_response :payment_required,
              "Tampered credential should yield 402 (new challenge), not 401"
            assert response.headers["WWW-Authenticate"].present?
          end

          test "Bearer + expired Payment credential returns 402 re-challenge" do
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            expired = build_expired_credential

            post api_v1_mpp_episodes_path,
              params: @valid_params,
              headers: combined_auth_header(token.plain_token, expired),
              as: :json

            assert_response :payment_required,
              "Expired credential should yield 402 (new challenge)"
          end

          # -------------------------------------------------------------------
          # Podcast attachment (GetsDefaultPodcastForUser)
          # -------------------------------------------------------------------

          test "user with 1 podcast: Episode attaches to that podcast" do
            user = users(:one) # user 'one' has podcast 'one' via podcast_memberships
            token = GeneratesApiToken.call(user: user)
            existing_podcast = user.podcasts.first
            assert_not_nil existing_podcast,
              "Fixture precondition: user 'one' must already have a podcast"

            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            assert_no_difference "Podcast.count" do
              post api_v1_mpp_episodes_path,
                params: @valid_params.merge(voice: "felix"),
                headers: combined_auth_header(token.plain_token, credential),
                as: :json
            end

            assert_response :created
            assert_equal existing_podcast.id, Episode.last.podcast_id
          end

          test "user with 0 podcasts: Episode attaches to an auto-created default podcast" do
            # free_user starts with no podcast_memberships fixture →
            # GetsDefaultPodcastForUser creates one on the fly.
            user = users(:free_user)
            token = GeneratesApiToken.call(user: user)
            assert_empty user.podcasts,
              "Fixture precondition: free_user should start with no podcasts"

            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            assert_difference "Podcast.count", 1 do
              post api_v1_mpp_episodes_path,
                params: @valid_params.merge(voice: "felix"),
                headers: combined_auth_header(token.plain_token, credential),
                as: :json
            end

            assert_response :created
            user.reload
            assert_equal 1, user.podcasts.count
            assert_equal user.podcasts.first.id, Episode.last.podcast_id
          end

          test "user with 2 podcasts: Episode attaches to podcasts.first (silent existing behavior)" do
            user = users(:two) # user 'two' has podcast 'two' fixture linkage
            # Add a second podcast so user has 2 total.
            second_podcast = Podcast.create!(
              podcast_id: "podcast_second_#{SecureRandom.hex(4)}",
              title: "Second Podcast",
              description: "Second podcast for multi-podcast test"
            )
            PodcastMembership.create!(user: user, podcast: second_podcast)
            user.reload
            assert_equal 2, user.podcasts.count,
              "Precondition: user must have 2 podcasts for this test"

            first_podcast = user.podcasts.first
            token = GeneratesApiToken.call(user: user)
            credential = valid_credential(
              voice_tier: :standard,
              amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

            post api_v1_mpp_episodes_path,
              params: @valid_params.merge(voice: "felix"),
              headers: combined_auth_header(token.plain_token, credential),
              as: :json

            assert_response :created
            # Documents existing GetsDefaultPodcastForUser#call behavior:
            # @user.podcasts.first — no explicit "default" flag exists yet.
            assert_equal first_podcast.id, Episode.last.podcast_id
          end

          # -------------------------------------------------------------------
          # User default voice (ResolvesVoice hierarchy: requested → saved → catalog)
          # -------------------------------------------------------------------

          test "user with saved voice_preference=callum, no voice param → resolves to callum (Premium, 100c)" do
            # Step 2 of ResolvesVoice hierarchy: authenticated user's saved
            # voice_preference fills in when no :voice param is sent. 'callum'
            # is Premium tier, so the 402 challenge must come in at 100c.
            user = users(:free_user)
            user.update!(voice_preference: "callum")
            token = GeneratesApiToken.call(user: user)

            post api_v1_mpp_episodes_path,
              params: @valid_params, # no :voice key
              headers: bearer_header(token.plain_token),
              as: :json

            assert_response :payment_required
            json = response.parsed_body
            assert_equal AppConfig::Mpp::PRICE_PREMIUM_CENTS, json["challenge"]["amount"]
            assert_equal 100, json["challenge"]["amount"]
          end

          test "user with saved voice_preference=callum + Premium credential, no voice param → 201 with voice_override=callum" do
            # Same ResolvesVoice hierarchy as above, but on the happy path:
            # user's saved preference surfaces in job args as voice_override
            # pointing to the Premium google voice. This is the 201-side
            # companion of the 402 tier-pricing test.
            user = users(:free_user)
            user.update!(voice_preference: "callum")
            token = GeneratesApiToken.call(user: user)
            credential = valid_credential(
              voice_tier: :premium,
              amount_cents: AppConfig::Mpp::PRICE_PREMIUM_CENTS
            )
            stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_PREMIUM_CENTS)

            assert_difference "Episode.count", 1 do
              post api_v1_mpp_episodes_path,
                params: @valid_params, # no :voice key — user pref drives
                headers: combined_auth_header(token.plain_token, credential),
                as: :json
            end

            assert_response :created
            assert_equal "en-GB-Chirp3-HD-Enceladus", enqueued_voice_override,
              "ResolvesVoice must resolve to user's saved preference (callum) " \
                "and propagate its google voice via voice_override"
          end

          private

          # Extract voice_override from the most recently enqueued processing
          # job. Option A sidecar: controller → ::Mpp::CreatesEpisode(voice:) →
          # ProcessesFileEpisodeJob.perform_later(voice_override:). Asserts
          # the exact job arg the Implementer must wire.
          #
          # Fails loudly if no job was enqueued OR if voice_override is missing
          # — either of which should surface as a clear failure message rather
          # than a silent nil.
          def enqueued_voice_override
            jobs = enqueued_jobs.select do |job|
              job[:job] == ProcessesFileEpisodeJob ||
                job["job_class"] == "ProcessesFileEpisodeJob"
            end
            assert_not_empty jobs,
              "Expected a ProcessesFileEpisodeJob to be enqueued; none found. " \
                "enqueued_jobs=#{enqueued_jobs.inspect}"

            args = jobs.last[:args] || jobs.last["arguments"] || []
            kwargs = args.last
            assert kwargs.is_a?(Hash),
              "Expected ProcessesFileEpisodeJob to be enqueued with keyword arguments; got args=#{args.inspect}"

            key = kwargs.key?(:voice_override) ? :voice_override : "voice_override"
            assert kwargs.key?(key),
              "Expected voice_override in ProcessesFileEpisodeJob kwargs; got keys=#{kwargs.keys.inspect}"
            kwargs[key]
          end

          def bearer_header(token)
            { "Authorization" => "Bearer #{token}" }
          end

          def payment_only_header(credential)
            { "Authorization" => "Payment #{credential}" }
          end

          def combined_auth_header(bearer_token, credential)
            { "Authorization" => "Bearer #{bearer_token}, Payment #{credential}" }
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
      end
    end
  end
end
