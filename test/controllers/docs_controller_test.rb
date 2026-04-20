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

  # --- iny7: MPP docs must be untouched ---
  # MPP is explicitly out of scope for iny7. This snapshot hash pins the
  # file's exact bytes so any edit (including an accidental copy sweep) is
  # caught by test. If MPP docs need to change, a separate bead updates
  # them and this hash is bumped deliberately.
  PRE_INY7_MPP_SHA256 = "4ea6c6789266a31c9efbb5933e39747e84cab5fa2a9842de5fdfe4eb3d7836da"

  test "app/views/docs/mpp.html.erb is unchanged from pre-iny7 bytes" do
    path = Rails.root.join("app/views/docs/mpp.html.erb")
    current = Digest::SHA256.hexdigest(File.read(path))
    assert_equal PRE_INY7_MPP_SHA256, current,
      "docs/mpp.html.erb has changed. MPP is out of scope for iny7 — " \
      "if this change is intentional, update PRE_INY7_MPP_SHA256."
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
