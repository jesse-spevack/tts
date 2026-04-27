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
  # MPP-scoped bead edits the file. Last bumped for agent-team-3ore
  # (add 'Other clients' subsection — mppx + @stripe/link-cli
  # positioning), replacing the pre-3ore snapshot from agent-team-cd53.
  MPP_DOCS_SHA256 = "fb60b0c194c20598efb133163388a458ee90ddf71e86dbcc8c457709648304a7"

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

  # --- Snapshot pin for docs/episodes.html.erb ---
  # Pins the file's exact bytes so any accidental copy sweep from an
  # unrelated bead is caught by test. Bumped deliberately whenever an
  # episodes-scoped bead edits the file. Established by agent-team-zhnc.
  EPISODES_DOCS_SHA256 = "6c3dd2a816a0a528faab606092e29de04c1da6210dff89221f9649b197eb3c9f"

  test "app/views/docs/episodes.html.erb bytes match the pinned snapshot" do
    path = Rails.root.join("app/views/docs/episodes.html.erb")
    current = Digest::SHA256.hexdigest(File.read(path))
    assert_equal EPISODES_DOCS_SHA256, current,
      "docs/episodes.html.erb has changed. If this change is intentional " \
      "and scoped to an episodes bead, bump EPISODES_DOCS_SHA256 to the new hash."
  end

  # --- iny7: docs/authentication rewrite ---

  test "GET /docs/authentication explains credit-based API access" do
    get docs_authentication_path
    assert_response :ok
    # Language signals that API use consumes credits, not a subscription.
    assert_match(/credits?/i, response.body)
    refute_match(/subscription-gated/i, response.body)
  end

  # --- Snapshot pin for docs/authentication.html.erb ---
  # Pins the file's exact bytes so any accidental copy sweep from an
  # unrelated bead is caught by test. Bumped deliberately whenever an
  # authentication-scoped bead edits the file. Established by agent-team-zhnc.
  AUTHENTICATION_DOCS_SHA256 = "83a61c9ffdc048f30eb2b22391932ffe8c380486a56121a03c884e184d438792"

  test "app/views/docs/authentication.html.erb bytes match the pinned snapshot" do
    path = Rails.root.join("app/views/docs/authentication.html.erb")
    current = Digest::SHA256.hexdigest(File.read(path))
    assert_equal AUTHENTICATION_DOCS_SHA256, current,
      "docs/authentication.html.erb has changed. If this change is intentional " \
      "and scoped to an authentication bead, bump AUTHENTICATION_DOCS_SHA256 to the new hash."
  end
end
