# frozen_string_literal: true

require "test_helper"

class CreateEpisodeFromUrlToolTest < ActiveSupport::TestCase
  # URL MCP submissions route through the unified cost service (gafe), which
  # returns Cost.deferred for URL source — real article length is unknown at
  # gate time. The anticipated-cost gate passes any balance, consistent with
  # the web / API v1 / email paths (all post-brick-3). Episode is created;
  # the async job handles the real debit once FetchesArticleContent knows the
  # length, and fails the episode async if balance falls short at that point.
  test "URL MCP submission defers the cost gate (pkbe) and creates the episode" do
    subscriber = users(:complimentary_user)
    CreditBalance.for(subscriber).update!(balance: 0)

    response = nil
    assert_difference -> { Episode.count }, 1 do
      assert_no_difference -> { CreditTransaction.count } do
        response = CreateEpisodeFromUrlTool.call(
          url: "https://example.com/article",
          server_context: { user: subscriber }
        )
      end
    end

    refute response.error?,
      "URL MCP submission must not fail at gate time — cost is deferred until fetch"
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
