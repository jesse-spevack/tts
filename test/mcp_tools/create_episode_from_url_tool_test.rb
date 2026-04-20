# frozen_string_literal: true

require "test_helper"

class CreateEpisodeFromUrlToolTest < ActiveSupport::TestCase
  test "subscriber with zero credits gets insufficient-credits error without creating Episode" do
    subscriber = users(:subscriber)
    CreditBalance.for(subscriber).update!(balance: 0)

    response = nil
    assert_no_difference -> { Episode.count } do
      assert_no_difference -> { CreditTransaction.count } do
        response = CreateEpisodeFromUrlTool.call(
          url: "https://example.com/article",
          server_context: { user: subscriber }
        )
      end
    end

    assert response.error?, "Response should be flagged as an error"
    payload = JSON.parse(response.content.first[:text])
    assert_equal "insufficient_credits", payload["error"]
  end

  test "credit user with balance 1 creates URL episode without syncing debit (defers to job)" do
    credit_user = users(:credit_user)
    CreditBalance.for(credit_user).update!(balance: 1)

    response = nil
    assert_difference -> { Episode.count }, 1 do
      # No CreditTransaction should be written at submit time — the job
      # is responsible for pricing once the article has been fetched.
      assert_no_difference -> { CreditTransaction.count } do
        response = CreateEpisodeFromUrlTool.call(
          url: "https://example.com/article",
          server_context: { user: credit_user }
        )
      end
    end

    refute response.error?, "Response should be success"
    assert_equal 1, credit_user.reload.credits_remaining
  end
end
