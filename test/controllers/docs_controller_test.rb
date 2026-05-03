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

  # --- agent-team-70dc: getting-started walkthrough ---

  test "GET /docs/mpp/getting-started renders the walkthrough" do
    get docs_mpp_getting_started_path

    assert_response :ok
    assert_select "h1", text: /MPP getting started/i
    # Sections we promised in the spec.
    assert_select "section#prerequisites"
    assert_select "section#rabby"
    assert_select "section#bridge"
    assert_select "section#mppx"
    assert_select "section#request"
    assert_select "section#audio"
    assert_select "section#pitfalls"
    assert_select "section#costs"
  end

  test "GET /docs/mpp/getting-started does not require authentication" do
    get docs_mpp_getting_started_path

    assert_response :ok
  end

  test "GET /docs/mpp/getting-started warns about Coinbase Wallet token-list gap" do
    get docs_mpp_getting_started_path

    assert_response :ok
    assert_match(/Coinbase Wallet/, response.body)
    assert_match(/Rabby/, response.body)
  end

  test "GET /docs/mpp/getting-started documents Tempo network params" do
    get docs_mpp_getting_started_path

    assert_response :ok
    assert_match("rpc.tempo.xyz", response.body)
    assert_match("4217", response.body)
  end

  test "GET /docs/mpp links to getting-started walkthrough" do
    get docs_mpp_path

    assert_response :ok
    assert_select "a[href=?]", docs_mpp_getting_started_path
  end

  # --- Snapshot pin for docs/mpp.html.erb ---
  # Pins the file's exact bytes so any accidental copy sweep from an
  # unrelated bead is caught by test. Bumped deliberately whenever an
  # MPP-scoped bead edits the file. Last bumped for agent-team-k71e.7
  # (link-cli flip to supported + per-scheme pricing + stripe-method
  # protocol branch), replacing the pre-k71e.7 snapshot from agent-team-udkz.
  MPP_DOCS_SHA256 = "744d0ff4d167aae0f3192a603a504df15374104ed3cae8f6942c9d391da8fea7"

  test "app/views/docs/mpp.html.erb bytes match the pinned snapshot" do
    path = Rails.root.join("app/views/docs/mpp.html.erb")
    current = Digest::SHA256.hexdigest(File.read(path))
    assert_equal MPP_DOCS_SHA256, current,
      "docs/mpp.html.erb has changed. If this change is intentional " \
      "and scoped to an MPP bead, bump MPP_DOCS_SHA256 to the new hash."
  end

  # --- agent-team-bmiz: link-cli walkthrough ---

  test "GET /docs/mpp/link-cli renders the walkthrough" do
    get docs_mpp_link_cli_path

    assert_response :ok
    assert_select "h1", text: /link-cli/i
    assert_select "section#install"
    assert_select "section#login"
    assert_select "section#payment-methods"
    assert_select "section#probe"
    assert_select "section#spend-request"
    assert_select "section#approve"
    assert_select "section#pay"
    assert_select "section#poll"
  end

  test "GET /docs/mpp/link-cli does not require authentication" do
    get docs_mpp_link_cli_path

    assert_response :ok
  end

  test "GET /docs/mpp/link-cli notes the zsh quoting requirement for csmrpd_* ids" do
    get docs_mpp_link_cli_path

    assert_response :ok
    assert_match(/zsh/i, response.body)
    assert_match(/csmrpd_/, response.body)
  end

  test "GET /docs/mpp/link-cli advertises PodRead's networkId" do
    get docs_mpp_link_cli_path

    assert_response :ok
    assert_match("profile_61UbsYpl4SxclGNZQA6UbsYpSGSQ2OwdqYukbeHlQOwS", response.body)
  end

  test "GET /docs/mpp/link-cli documents the per-scheme prices for both tiers" do
    get docs_mpp_link_cli_path

    assert_response :ok
    assert_match(/\$0\.75/, response.body)
    assert_match(/\$1\.50/, response.body)
    assert_match(/\$2\.00/, response.body)
    assert_match(/\$2\.50/, response.body)
  end

  test "GET /docs/mpp links to the link-cli walkthrough" do
    get docs_mpp_path

    assert_response :ok
    assert_select "a[href=?]", docs_mpp_link_cli_path
  end

  # --- Snapshot pin for docs/mpp/link_cli.html.erb ---
  # Pins the new walkthrough's bytes per the snapshot-pin convention.
  # Established by agent-team-bmiz.
  MPP_LINK_CLI_DOCS_SHA256 = "9dd4ce340fca600818f18643de7cfc5723a0ac01d4f9d9a11902fc85e5827337"

  test "app/views/docs/mpp_link_cli.html.erb bytes match the pinned snapshot" do
    path = Rails.root.join("app/views/docs/mpp_link_cli.html.erb")
    current = Digest::SHA256.hexdigest(File.read(path))
    assert_equal MPP_LINK_CLI_DOCS_SHA256, current,
      "docs/mpp_link_cli.html.erb has changed. If this change is intentional " \
      "and scoped to an MPP bead, bump MPP_LINK_CLI_DOCS_SHA256 to the new hash."
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
  # episodes-scoped bead edits the file. Last bumped for agent-team-udkz
  # (left-rail nav layout), established by agent-team-zhnc.
  EPISODES_DOCS_SHA256 = "e9ba0855b782f7c4244b2cae8466c48d5f3ed28c9078a6fc90ed3ccb2c26b26c"

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
  # authentication-scoped bead edits the file. Last bumped for
  # agent-team-udkz (left-rail nav layout), established by agent-team-zhnc.
  AUTHENTICATION_DOCS_SHA256 = "71eb60819f9168e0bef31dd009ab9dcce15150aa030cc86b182b3ae431035094"

  test "app/views/docs/authentication.html.erb bytes match the pinned snapshot" do
    path = Rails.root.join("app/views/docs/authentication.html.erb")
    current = Digest::SHA256.hexdigest(File.read(path))
    assert_equal AUTHENTICATION_DOCS_SHA256, current,
      "docs/authentication.html.erb has changed. If this change is intentional " \
      "and scoped to an authentication bead, bump AUTHENTICATION_DOCS_SHA256 to the new hash."
  end
end
