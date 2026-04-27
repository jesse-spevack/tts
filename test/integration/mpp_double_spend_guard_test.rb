# frozen_string_literal: true

require "test_helper"

# Regression: prevent MppPayment double-spend race (agent-team-kzq).
#
# Two simultaneous POSTs with the same verified credential used to
# both pass Mpp::VerifiesCredential (the MppPayment.exists?(tx_hash:)
# replay check races the update!), both find the same pending
# MppPayment by challenge_id, both call update!, and both create a
# Narration / Episode. One payment → two resources.
#
# The fix is an atomic status transition at the controller layer:
#     MppPayment.where(id:, status: :pending).update_all(status: :completed)
# with a row-count check. The winner (rows == 1) proceeds to create
# the resource; the loser (rows == 0) returns an idempotent 201
# pointing at the winner's resource (narration path, which links via
# narrations.mpp_payment_id) or a 409 Conflict (episode path, which
# does not currently link episodes.mpp_payment_id).
#
# Narrations also get a DB-level unique index on mpp_payment_id as a
# belt-and-suspenders backstop (db/migrate/..._add_unique_index_...).
class MppDoubleSpendGuardTest < ActiveSupport::TestCase
  # Shared setup: a single pending MppPayment that both racing threads
  # will contend for. Mirrors the state the controller reaches after
  # Mpp::VerifiesCredential succeeds on both racing requests.
  setup do
    @mpp_payment = MppPayment.create!(
      amount_cents: 75,
      currency: "usd",
      challenge_id: "challenge_#{SecureRandom.hex(8)}",
      deposit_address: "0xdeposit#{SecureRandom.hex(16)}",
      stripe_payment_intent_id: "pi_test_#{SecureRandom.hex(8)}",
      status: :pending
    )
    @tx_hash = "0x#{SecureRandom.hex(32)}"
  end

  # === Atomic MppPayment status transition ===
  #
  # The load-bearing primitive. If this is wrong, every controller
  # guarding the race is also wrong. Test it in isolation first.

  test "atomic pending→completed flip: exactly one of N concurrent updates wins" do
    thread_count = 5

    results = thread_count.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          MppPayment.where(id: @mpp_payment.id, status: "pending").update_all(
            status: "completed",
            tx_hash: @tx_hash,
            updated_at: Time.current
          )
        end
      end
    end.map(&:value)

    winners = results.count { |n| n == 1 }
    losers = results.count { |n| n == 0 }

    assert_equal 1, winners, "Exactly one thread should have flipped the row"
    assert_equal thread_count - 1, losers, "All other threads should see row-count 0"
    assert_equal "completed", @mpp_payment.reload.status
    assert_equal @tx_hash, @mpp_payment.tx_hash
  end

  # === Narration path: unique index backstop ===
  #
  # Even if the controller guard were bypassed, the DB must refuse a
  # second Narration for the same mpp_payment_id. This exercises the
  # unique index added in the migration.

  test "narrations.mpp_payment_id unique index prevents duplicate rows" do
    Narration.create!(
      mpp_payment: @mpp_payment,
      title: "First",
      source_type: :text,
      source_text: "x",
      expires_at: 24.hours.from_now
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      Narration.create!(
        mpp_payment: @mpp_payment,
        title: "Second",
        source_type: :text,
        source_text: "y",
        expires_at: 24.hours.from_now
      )
    end
  end
end

# End-to-end race test via the anonymous MPP narrations controller.
# Verifies the full HTTP path: two racing POSTs with the same credential
# must produce at most one Narration and one MppPayment in :completed
# status.
class MppDoubleSpendNarrationsIntegrationTest < ActionDispatch::IntegrationTest
  TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  setup do
    @currency = AppConfig::Mpp::CURRENCY
    @tx_hash = "0x#{SecureRandom.hex(32)}"
    @deposit_address = "0xdeposit#{SecureRandom.hex(16)}"

    Stripe.api_key = "sk_test_fake"

    @valid_params = {
      title: "Test Article",
      author: "Test Author",
      description: "A test article description",
      content: "This is the full content of the article. " * 50,
      url: "https://example.com/article",
      source_type: "url",
      voice: "felix"
    }
  end

  test "sequential repeat with same credential: only one Narration, second request is idempotent or clean error" do
    # This exercises the controller guard without threading — the first
    # request completes the MppPayment; the second request hits the
    # guard and must NOT create a second Narration. In production the
    # race window is a few ms; serializing the test keeps it
    # deterministic while still proving the guard is wired in.
    credential = valid_credential(
      voice_tier: :standard,
      amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS
    )
    stub_tempo_rpc_success(amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS)

    # First request — must succeed and create exactly one Narration.
    assert_difference "Narration.count", 1 do
      post api_v1_mpp_narrations_path,
        params: @valid_params,
        headers: payment_only_header(credential),
        as: :json
    end
    assert_response :created
    mpp_payment = MppPayment.find_by!(tx_hash: @tx_hash)
    assert_equal "completed", mpp_payment.status
    existing_narration = Narration.find_by!(mpp_payment_id: mpp_payment.id)

    # Second request with the SAME credential. VerifiesCredential's
    # replay check (MppPayment.exists?(tx_hash:)) will now reject this
    # deterministically — which is the production behavior for a
    # serial retry. The race window only opens when BOTH requests
    # enter VerifiesCredential before either one persists tx_hash.
    # So the serial test asserts the replay guard is active; the
    # threaded test below asserts the race-window guard.
    assert_no_difference "Narration.count" do
      post api_v1_mpp_narrations_path,
        params: @valid_params,
        headers: payment_only_header(credential),
        as: :json
    end
    assert_equal 1, Narration.where(mpp_payment_id: mpp_payment.id).count
    assert_equal existing_narration.id, Narration.find_by(mpp_payment_id: mpp_payment.id).id
  end

  test "concurrent critical-section race: at most one Narration created per MppPayment" do
    # Simulate the race WINDOW: both threads have already passed
    # VerifiesCredential (tx_hash replay check has not yet been
    # recorded), both are now about to flip the pending MppPayment
    # to completed and create a Narration.
    #
    # The controller guard (atomic update_all + row-count check) must
    # serialize this so only ONE Narration is created.
    mpp_payment = MppPayment.create!(
      amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS,
      currency: @currency,
      challenge_id: "challenge_#{SecureRandom.hex(8)}",
      deposit_address: @deposit_address,
      stripe_payment_intent_id: "pi_test_#{SecureRandom.hex(8)}",
      status: :pending
    )

    # Invoke the guarded critical section (extracted service) from N
    # threads sharing the same MppPayment. This is the exact code
    # path the controller takes after VerifiesCredential succeeds.
    thread_count = 5
    results = thread_count.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ::Mpp::FinalizesNarration.call(
            mpp_payment: mpp_payment,
            tx_hash: @tx_hash,
            params: {
              title: "Racing Title",
              author: "Racing Author",
              source_type: "text",
              content: "Racing body content.",
              voice: "felix"
            }
          )
        end
      end
    end.map(&:value)

    # Exactly one winner creates a Narration; losers return the
    # winner's Narration (idempotent) or a conflict — never a second
    # row.
    assert_equal 1, Narration.where(mpp_payment_id: mpp_payment.id).count,
      "Double-spend guard failed: more than one Narration created for the same MppPayment"
    assert_equal "completed", mpp_payment.reload.status

    winner_outcomes = results.count { |r| r.data[:outcome] == :winner }
    loser_outcomes = results.count { |r| r.data[:outcome] == :loser }
    assert_equal 1, winner_outcomes, "Expected exactly one winner"
    assert_equal thread_count - 1, loser_outcomes, "Remaining threads must be losers"

    # All responders — winner and losers — must reference the SAME
    # Narration (idempotent semantics).
    narration_ids = results.map { |r| r.data[:narration].id }.uniq
    assert_equal 1, narration_ids.size,
      "All responders must reference the same Narration"
  end

  private

  def payment_only_header(credential)
    { "Authorization" => "Payment #{credential}" }
  end

  def provision_challenge(voice_tier:, amount_cents:, deposit_address: @deposit_address)
    ::Mpp::CreatesDepositAddress.call(
      amount_cents: amount_cents,
      currency: @currency
    )

    challenge = ::Mpp::GeneratesChallenge.call(
      amount_cents: amount_cents,
      recipient: deposit_address,
      voice_tier: voice_tier
    ).data

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
    stub_request(:post, "https://api.stripe.com/v1/payment_intents")
      .to_return(status: 200, body: {
        id: "pi_test_#{SecureRandom.hex(8)}",
        object: "payment_intent",
        amount: amount_cents,
        currency: @currency,
        status: "requires_action",
        next_action: {
          type: "crypto_display_details",
          crypto_display_details: {
            deposit_addresses: {
              tempo: { address: @deposit_address }
            }
          }
        }
      }.to_json, headers: { "Content-Type" => "application/json" })

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

  def pad_address(address)
    clean = address.delete_prefix("0x").downcase
    "0x" + clean.rjust(64, "0")
  end

  def amount_to_hex(amount_cents)
    base_units = (amount_cents * (10**AppConfig::Mpp::TEMPO_TOKEN_DECIMALS)) / 100
    "0x" + base_units.to_s(16).rjust(64, "0")
  end
end

# Same race test for the authenticated Episode path.
#
# Episodes differ from Narrations in one important way: episodes.mpp_payment_id
# is NOT populated by the MPP create flow today, so we cannot look up the
# winner's Episode by mpp_payment_id. Loser semantics here are therefore
# "clean error" rather than "idempotent retry" — the guard returns
# :loser with nil episode, which the controller maps to 409 Conflict.
class MppDoubleSpendEpisodesIntegrationTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
    @currency = AppConfig::Mpp::CURRENCY
    @tx_hash = "0x#{SecureRandom.hex(32)}"
    @deposit_address = "0xdeposit#{SecureRandom.hex(16)}"

    @mpp_payment = MppPayment.create!(
      amount_cents: AppConfig::Mpp::PRICE_STANDARD_CENTS,
      currency: @currency,
      challenge_id: "challenge_#{SecureRandom.hex(8)}",
      deposit_address: @deposit_address,
      stripe_payment_intent_id: "pi_test_#{SecureRandom.hex(8)}",
      status: :pending
    )
  end

  test "concurrent critical-section race: at most one Episode created per MppPayment" do
    thread_count = 5
    results = thread_count.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ::Mpp::FinalizesEpisode.call(
            user: @user,
            mpp_payment: @mpp_payment,
            tx_hash: @tx_hash,
            params: {
              title: "Racing Title",
              author: "Racing Author",
              description: "Racing description",
              content: "Racing body content — long enough to pass the MIN_LENGTH validator. " * 5,
              source_type: "extension",
              url: "https://example.com"
            },
            voice_override: "en-GB-Standard-D"
          )
        end
      end
    end.map(&:value)

    assert_equal 1, Episode.where(user: @user).count,
      "Double-spend guard failed: more than one Episode created for the same MppPayment"
    assert_equal "completed", @mpp_payment.reload.status
    assert_equal @user.id, @mpp_payment.user_id

    winner_outcomes = results.count { |r| r.data[:outcome] == :winner }
    loser_outcomes = results.count { |r| r.data[:outcome] == :loser }
    assert_equal 1, winner_outcomes, "Expected exactly one winner"
    assert_equal thread_count - 1, loser_outcomes, "Remaining threads must be losers"
  end
end
