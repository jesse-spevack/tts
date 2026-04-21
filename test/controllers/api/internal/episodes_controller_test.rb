require "test_helper"

module Api
  module Internal
    class EpisodesControllerTest < ActionDispatch::IntegrationTest
      setup do
        result = CreatesUser.call(email_address: "test@example.com")
        @user = result.data[:user]
        @podcast = result.data[:podcast]
        @episode = @podcast.episodes.create!(
          title: "Test Episode",
          author: "Test Author",
          description: "Test description",
          user: @user,
          source_type: :url,
          source_url: "https://example.com/test-article",
          status: :processing
        )
        @secret = "test-callback-secret"
        ENV["GENERATOR_CALLBACK_SECRET"] = @secret
      end

      test "update marks episode complete with valid secret" do
        patch api_internal_episode_url(@episode),
          params: {
            status: "complete",
            gcs_episode_id: "episode_abc123",
            audio_size_bytes: 1_000_000,
            duration_seconds: 754
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        @episode.reload
        assert_equal "complete", @episode.status
        assert_equal "episode_abc123", @episode.gcs_episode_id
        assert_equal 1_000_000, @episode.audio_size_bytes
        assert_equal 754, @episode.duration_seconds
      end

      test "update marks episode failed with error message" do
        patch api_internal_episode_url(@episode),
          params: {
            status: "failed",
            error_message: "TTS service unavailable"
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        @episode.reload
        assert_equal "failed", @episode.status
        assert_equal "TTS service unavailable", @episode.error_message
      end

      test "update rejects invalid secret" do
        patch api_internal_episode_url(@episode),
          params: { status: "complete" }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => "wrong-secret"
          }

        assert_response :unauthorized
        @episode.reload
        assert_equal "processing", @episode.status
      end

      test "update rejects missing secret" do
        patch api_internal_episode_url(@episode),
          params: { status: "complete" }.to_json,
          headers: { "Content-Type" => "application/json" }

        assert_response :unauthorized
      end

      test "update returns 404 for non-existent episode" do
        patch api_internal_episode_url(id: 99999),
          params: { status: "complete" }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :not_found
      end

      test "update rejects invalid status" do
        patch api_internal_episode_url(@episode),
          params: { status: "invalid_status" }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :unprocessable_entity
        @episode.reload
        assert_equal "processing", @episode.status
      end

      test "update is idempotent for duplicate completions" do
        @episode.update!(status: :complete, gcs_episode_id: "episode_abc123")

        patch api_internal_episode_url(@episode),
          params: {
            status: "complete",
            gcs_episode_id: "episode_abc123",
            audio_size_bytes: 1_000_000
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
      end

      test "refunds episode usage when status is failed for free user" do
        free_user = users(:free_user)
        @episode.update!(user: free_user)

        EpisodeUsage.create!(
          user: free_user,
          period_start: Time.current.beginning_of_month.to_date,
          episode_count: 1
        )

        patch api_internal_episode_url(@episode),
          params: {
            status: "failed",
            error_message: "Processing failed"
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        usage = EpisodeUsage.current_for(free_user)
        assert_equal 0, usage.episode_count
      end

      test "does not refund usage when status is complete" do
        free_user = users(:free_user)
        @episode.update!(user: free_user)

        EpisodeUsage.create!(
          user: free_user,
          period_start: Time.current.beginning_of_month.to_date,
          episode_count: 1
        )

        patch api_internal_episode_url(@episode),
          params: {
            status: "complete",
            gcs_episode_id: "abc123"
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        usage = EpisodeUsage.current_for(free_user)
        assert_equal 1, usage.episode_count
      end

      test "handles failure update when no usage record exists" do
        patch api_internal_episode_url(@episode),
          params: {
            status: "failed",
            error_message: "Processing failed"
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        @episode.reload
        assert_equal "failed", @episode.status
      end

      test "calls NotifiesEpisodeCompletion when episode completes" do
        @episode.update!(status: :pending)

        assert_emails 1 do
          patch api_internal_episode_url(@episode),
            params: { status: "complete", gcs_episode_id: "episode_abc123" }.to_json,
            headers: { "Content-Type" => "application/json", "X-Generator-Secret" => @secret }
        end
      end

      test "does not send email when episode fails" do
        @episode.update!(status: :pending)

        assert_no_emails do
          patch api_internal_episode_url(@episode),
            params: { status: "failed", error_message: "Processing error" }.to_json,
            headers: { "Content-Type" => "application/json", "X-Generator-Secret" => @secret }
        end
      end

      test "does not send duplicate emails on repeated completion updates" do
        @episode.update!(status: :pending)

        # First completion - should send email
        assert_emails 1 do
          patch api_internal_episode_url(@episode),
            params: { status: "complete", gcs_episode_id: "episode_abc123" }.to_json,
            headers: { "Content-Type" => "application/json", "X-Generator-Secret" => @secret }
        end

        # Second completion - should not send email
        assert_no_emails do
          patch api_internal_episode_url(@episode),
            params: { status: "complete", gcs_episode_id: "episode_abc123" }.to_json,
            headers: { "Content-Type" => "application/json", "X-Generator-Secret" => @secret }
        end
      end

      # === Credit refund on failure callback (agent-team-uoqd) ===
      #
      # Symmetric with the existing "refunds episode usage when status is
      # failed for free user" test above — when a credit user's episode
      # fails via this callback, their debited credit must be refunded.

      test "refunds debited credit when status is failed for credit user" do
        credit_user = users(:credit_user)
        CreditBalance.for(credit_user).update!(balance: 3)
        @episode.update!(user: credit_user)
        DeductsCredit.call(user: credit_user, episode: @episode, cost_in_credits: 1)
        assert_equal 2, credit_user.reload.credits_remaining

        patch api_internal_episode_url(@episode),
          params: {
            status: "failed",
            error_message: "Processing failed"
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        assert_equal 3, credit_user.reload.credits_remaining,
          "Credit user's debited credit should be refunded on failure callback"
      end

      test "duplicate failure callback does not double-refund credit" do
        credit_user = users(:credit_user)
        CreditBalance.for(credit_user).update!(balance: 3)
        @episode.update!(user: credit_user)
        DeductsCredit.call(user: credit_user, episode: @episode, cost_in_credits: 1)

        2.times do
          patch api_internal_episode_url(@episode),
            params: { status: "failed", error_message: "Processing failed" }.to_json,
            headers: {
              "Content-Type" => "application/json",
              "X-Generator-Secret" => @secret
            }
        end

        assert_equal 3, credit_user.reload.credits_remaining,
          "Two failure callbacks must not double-refund (idempotency via refund_<id> session_id)"
      end

      test "free-tier monthly counter still decrements on failure (no regression)" do
        # Guard: wiring RefundsCreditDebit into the update action must not
        # break the existing RefundsEpisodeUsage behavior for free users.
        free_user = users(:free_user)
        @episode.update!(user: free_user)

        EpisodeUsage.create!(
          user: free_user,
          period_start: Time.current.beginning_of_month.to_date,
          episode_count: 2
        )

        patch api_internal_episode_url(@episode),
          params: {
            status: "failed",
            error_message: "Processing failed"
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Generator-Secret" => @secret
          }

        assert_response :success
        usage = EpisodeUsage.current_for(free_user)
        assert_equal 1, usage.episode_count,
          "Free-tier counter must still decrement after RefundsCreditDebit is wired in"
        # And the free user had no credits involved — no refund txn created.
        assert_equal 0, CreditTransaction.where(user: free_user).count
      end
    end

    # === Cost-preview endpoint (agent-team-gq88) ===
    #
    # POST /api/internal/episodes/cost_preview
    #
    # Uses Rails session auth (Current.user), NOT the generator-secret auth
    # used by the PATCH update callback above. The Implementer decides
    # whether this lives on the same controller with per-action auth or on
    # a sibling controller — the route + action name is the contract.
    #
    # Response shape:
    #   { cost: 1|2, balance: Integer, sufficient: Bool, voice_tier: "standard"|"premium" }
    #
    # Non-credit-user shape (see tests below): we chose a dedicated marker
    # payload to keep the client a single JSON branch. The endpoint always
    # returns 200 on valid auth + input; the client decides whether to
    # render preview based on `free_tier`/`no_cost` flags rather than HTTP
    # status.
    class EpisodesCostPreviewTest < ActionDispatch::IntegrationTest
      setup do
        @credit_user = users(:credit_user)
        # Default: Standard voice (Felix), 5 credits.
        @credit_user.update!(voice_preference: "felix")
        CreditBalance.for(@credit_user).update!(balance: 5)
        sign_in_as(@credit_user)
      end

      # ---------- Routing ----------

      test "routes POST /api/internal/episodes/cost_preview to cost_preview action" do
        # Endpoint lives on a sibling controller (Api::Internal::CostPreviewController)
        # because it uses session auth rather than the X-Generator-Secret
        # header auth used by Api::Internal::EpisodesController#update.
        assert_routing(
          { method: :post, path: "/api/internal/episodes/cost_preview" },
          controller: "api/internal/cost_preview", action: "create"
        )
      end

      # ---------- Happy-path matrix (credit user, Standard voice) ----------

      test "paste 10k chars + standard voice → cost 1, standard tier" do
        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 10_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal 1, body["cost"]
        assert_equal 5, body["balance"]
        assert_equal true, body["sufficient"]
        assert_equal "standard", body["voice_tier"]
      end

      test "paste 25k chars + standard voice → cost 1 (Standard never pays 2)" do
        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 25_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal 1, body["cost"]
        assert_equal 5, body["balance"]
        assert_equal true, body["sufficient"]
        assert_equal "standard", body["voice_tier"]
      end

      # ---------- Happy-path matrix (credit user, Premium voice) ----------

      test "paste 10k chars + premium voice → cost 1, premium tier" do
        @credit_user.update!(voice_preference: "callum")

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 10_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal 1, body["cost"]
        assert_equal true, body["sufficient"]
        assert_equal "premium", body["voice_tier"]
      end

      test "paste 25k chars + premium voice → cost 2, premium tier" do
        @credit_user.update!(voice_preference: "callum")

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 25_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal 2, body["cost"]
        assert_equal true, body["sufficient"]
        assert_equal "premium", body["voice_tier"]
      end

      test "boundary: exactly 20k chars + premium voice → cost 1 (≤20k is always 1)" do
        @credit_user.update!(voice_preference: "callum")

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 20_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal 1, body["cost"]
        assert_equal "premium", body["voice_tier"]
      end

      test "boundary: 20001 chars + premium voice → cost 2 (>20k triggers)" do
        @credit_user.update!(voice_preference: "callum")

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 20_001 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal 2, body["cost"]
        assert_equal "premium", body["voice_tier"]
      end

      # ---------- Source-type variants ----------

      test "url source_type returns cost 1 regardless of preview length" do
        @credit_user.update!(voice_preference: "callum")

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "url", url: "https://example.com/very-long-article" },
          as: :json

        assert_response :success
        body = response.parsed_body
        # URL shortcut: real length isn't known until fetch; CalculatesAnticipatedEpisodeCost
        # scores URL sources as length=1, which is always 1 credit.
        assert_equal 1, body["cost"]
        assert_equal "premium", body["voice_tier"]
      end

      test "upload source_type with upload_length=30000 + premium → cost 2" do
        @credit_user.update!(voice_preference: "callum")

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "upload", upload_length: 30_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal 2, body["cost"]
        assert_equal "premium", body["voice_tier"]
      end

      # ---------- Insufficient balance ----------

      test "credit user with balance 1 + 25k premium → cost 2, sufficient false" do
        @credit_user.update!(voice_preference: "callum")
        CreditBalance.for(@credit_user).update!(balance: 1)

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 25_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal 2, body["cost"]
        assert_equal 1, body["balance"]
        assert_equal false, body["sufficient"]
      end

      test "credit user with balance 0 + 10k standard → cost 1, sufficient false" do
        @credit_user.update!(voice_preference: "felix")
        CreditBalance.for(@credit_user).update!(balance: 0)

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 10_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal 1, body["cost"]
        assert_equal 0, body["balance"]
        assert_equal false, body["sufficient"]
      end

      # ---------- Auth ----------

      test "unauthenticated request returns 401" do
        sign_out

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 1_000 },
          as: :json

        assert_response :unauthorized
      end

      test "complimentary user receives free_tier marker payload (no cost preview applies)" do
        # Complimentary / unlimited users never pay credits. We chose a
        # distinct JSON marker so the client can render an "Included"
        # badge without having to distinguish 200+zero-balance from a
        # real insufficient-funds response. The shape is:
        #   { free_tier: true, cost: 0, voice_tier: "standard"|"premium" }
        complimentary = users(:complimentary_user)
        complimentary.update!(voice_preference: "felix")
        sign_in_as(complimentary)

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 10_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal true, body["free_tier"]
        assert_equal 0, body["cost"]
      end

      test "unlimited user receives free_tier marker payload" do
        unlimited = users(:unlimited_user)
        unlimited.update!(voice_preference: "callum")
        sign_in_as(unlimited)

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 25_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal true, body["free_tier"]
        assert_equal 0, body["cost"]
      end

      test "free-tier standard user receives free_tier marker payload (quota handled elsewhere)" do
        # Free users see "X of 2 free episodes this month" copy — the
        # form's existing quota UI. No cost preview is shown, so the
        # endpoint returns the same shape as complimentary/unlimited.
        free = users(:free_user)
        free.update!(voice_preference: "felix")
        sign_in_as(free)

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 10_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal true, body["free_tier"]
        assert_equal 0, body["cost"]
      end

      test "active subscriber with historical credit_balance row receives free_tier payload (balance not leaked)" do
        # Regression guard for the on_credit_path? unification. A user
        # who had credits in the past but is now on an active subscription
        # is premium — the UI correctly hides the preview. Before gq88's
        # fix-up pass the endpoint's gate didn't check premium?, so a
        # direct fetch would return the credit payload and leak their
        # historical balance. on_credit_path? closes that leak by
        # excluding premium? users regardless of credit history.
        subscriber = users(:subscriber)
        subscriber.update!(voice_preference: "callum")
        CreditBalance.create!(user: subscriber, balance: 42)
        sign_in_as(subscriber)

        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 25_000 },
          as: :json

        assert_response :success
        body = response.parsed_body
        assert_equal true, body["free_tier"],
          "Active subscriber must receive free_tier payload even with a credit_balance row"
        assert_nil body["balance"],
          "Endpoint must not leak the subscriber's credit balance to direct fetches"
      end

      # ---------- Response headers (agent-team-yx53) ----------

      test "response sets Cache-Control: private, no-store" do
        # Defense-in-depth: balance data must never be cached by intermediaries.
        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste", text: "A" * 10_000 },
          as: :json

        assert_response :success
        assert_equal "private, no-store", response.headers["Cache-Control"]
      end

      # ---------- Invalid input (422) ----------

      test "missing source_type returns 422" do
        post "/api/internal/episodes/cost_preview",
          params: { text: "A" * 1_000 },
          as: :json

        assert_response :unprocessable_entity
      end

      test "unknown source_type returns 422" do
        post "/api/internal/episodes/cost_preview",
          params: { source_type: "telepathy", text: "A" * 1_000 },
          as: :json

        assert_response :unprocessable_entity
      end

      test "source_type=paste without text returns 422" do
        post "/api/internal/episodes/cost_preview",
          params: { source_type: "paste" },
          as: :json

        assert_response :unprocessable_entity
      end

      test "source_type=url without url returns 422" do
        post "/api/internal/episodes/cost_preview",
          params: { source_type: "url" },
          as: :json

        assert_response :unprocessable_entity
      end

      test "source_type=upload without upload_length returns 422" do
        post "/api/internal/episodes/cost_preview",
          params: { source_type: "upload" },
          as: :json

        assert_response :unprocessable_entity
      end

      # ---------- Parity with the service ----------
      #
      # Guard against the endpoint drifting from CalculatesEpisodeCreditCost.
      # For each (length, voice) quadrant, both the service and the endpoint
      # must agree on cost.

      PARITY_MATRIX = [
        [ 10_000, "felix" ],
        [ 25_000, "felix" ],
        [ 10_000, "callum" ],
        [ 25_000, "callum" ],
        [ 20_000, "callum" ],
        [ 20_001, "callum" ]
      ].freeze

      PARITY_MATRIX.each do |length, voice_key|
        test "parity: length=#{length} voice=#{voice_key} — service and endpoint agree" do
          @credit_user.update!(voice_preference: voice_key)

          service_cost = CalculatesEpisodeCreditCost.call(
            source_text_length: length,
            voice: Voice.find(voice_key)
          )

          post "/api/internal/episodes/cost_preview",
            params: { source_type: "paste", text: "A" * length },
            as: :json

          assert_response :success
          assert_equal service_cost, response.parsed_body["cost"],
            "Endpoint disagrees with CalculatesEpisodeCreditCost for length=#{length} voice=#{voice_key}"
        end
      end
    end
  end
end
