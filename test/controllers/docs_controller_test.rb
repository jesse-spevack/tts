require "test_helper"
require "digest"

class DocsControllerTest < ActionDispatch::IntegrationTest
  test "GET /docs/mpp renders the MPP API reference" do
    get docs_mpp_path

    assert_response :ok
    assert_select "h1", text: /text into audio/i
    assert_select "a[href='http://mpp.dev/']"
    assert_select "section#voices"
    assert_select "section#rate-limits"
  end

  test "GET /docs/mpp does not require authentication" do
    get docs_mpp_path

    assert_response :ok
  end

  # --- Snapshot pin for docs/mpp.html.erb ---
  # Pins the file's exact bytes so any accidental copy sweep from an
  # unrelated bead is caught by test. Bumped deliberately whenever an
  # MPP-scoped bead edits the file. Last bumped for agent-team-cd53
  # (raise MPP Premium price from $1.00 to $1.50), replacing the
  # pre-cd53 snapshot from agent-team-rwzy.
  MPP_DOCS_SHA256 = "5b9fd8fea3387915f37ef4c0e9bd38deca45a5b52c747533167bed7b52851e69"

  test "app/views/docs/mpp.html.erb bytes match the pinned snapshot" do
    path = Rails.root.join("app/views/docs/mpp.html.erb")
    current = Digest::SHA256.hexdigest(File.read(path))
    assert_equal MPP_DOCS_SHA256, current,
      "docs/mpp.html.erb has changed. If this change is intentional " \
      "and scoped to an MPP bead, bump MPP_DOCS_SHA256 to the new hash."
  end

  # --- iny7: docs/episodes content rewrite ---

  test "GET /docs/episodes states the universal 50,000 character limit" do
    get docs_episodes_path
    assert_response :ok
    assert_match "50,000 characters", response.body
    # No more split: there shouldn't be a "free tier" character limit story
    # in the docs body after iny7.
    refute_match(/15,000/, response.body,
      "Free-tier 15k limit should no longer appear in /docs/episodes after iny7")
  end

  test "GET /docs/episodes documents the credit-cost-by-usage rule" do
    get docs_episodes_path
    assert_response :ok
    # The rule: 1 credit for episodes that fit ≤20k OR use a Standard voice,
    # 2 credits for the combination of >20k characters AND a Premium voice.
    assert_match(/1 credit/, response.body)
    assert_match(/2 credits/, response.body)
  end

  # --- iny7: docs/authentication rewrite ---

  test "GET /docs/authentication explains credit-based API access" do
    get docs_authentication_path
    assert_response :ok
    # Language signals that API use consumes credits, not a subscription.
    assert_match(/credits?/i, response.body)
    refute_match(/subscription-gated/i, response.body)
  end
end
