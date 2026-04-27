# frozen_string_literal: true

require "test_helper"

class CreateEpisodeFromTextToolTest < ActiveSupport::TestCase
  test "credit user with balance 1 and Premium long-form text gets insufficient-credits error without creating Episode" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "callum") # Premium
    CreditBalance.for(credit_user).update!(balance: 1)

    long_text = "A" * 30_000 # >20k chars + Premium = 2 credits

    response = nil
    assert_no_difference -> { Episode.count } do
      assert_no_difference -> { CreditTransaction.count } do
        response = CreateEpisodeFromTextTool.call(
          text: long_text,
          title: "Long Article",
          server_context: { user: credit_user }
        )
      end
    end

    assert response.error?, "Response should be flagged as an error"
    payload = JSON.parse(response.content.first[:text])
    assert_equal "insufficient_credits", payload["error"]
    assert_equal 1, credit_user.reload.credits_remaining
  end

  test "credit user with balance 2 and Premium long-form text succeeds and debits 2 credits" do
    credit_user = users(:credit_user)
    credit_user.update!(voice_preference: "callum") # Premium
    CreditBalance.for(credit_user).update!(balance: 2)

    long_text = "A" * 30_000

    response = nil
    assert_difference -> { Episode.count }, 1 do
      assert_difference -> { CreditTransaction.where(user: credit_user, transaction_type: "usage").count }, 1 do
        response = CreateEpisodeFromTextTool.call(
          text: long_text,
          title: "Long Article",
          server_context: { user: credit_user }
        )
      end
    end

    refute response.error?
    assert_equal 0, credit_user.reload.credits_remaining

    transaction = CreditTransaction.where(user: credit_user, transaction_type: "usage").order(:created_at).last
    assert_equal(-2, transaction.amount)
  end

  test "credit user with zero credits gets insufficient-credits error without creating Episode" do
    subscriber = users(:credit_user)
    CreditBalance.for(subscriber).update!(balance: 0)

    long_text = "A" * 1_000 # any length — balance is 0, cost is 1

    response = nil
    assert_no_difference -> { Episode.count } do
      assert_no_difference -> { CreditTransaction.count } do
        response = CreateEpisodeFromTextTool.call(
          text: long_text,
          title: "Article",
          server_context: { user: subscriber }
        )
      end
    end

    assert response.error?
    payload = JSON.parse(response.content.first[:text])
    assert_equal "insufficient_credits", payload["error"]
  end
end
