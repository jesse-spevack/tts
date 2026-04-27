# frozen_string_literal: true

require "test_helper"

# End-to-end flow test for the cost-preview endpoint (agent-team-gq88).
#
# The project doesn't run Capybara system tests (no test/system/ content),
# so Stimulus controller behavior can't be exercised directly. This test
# hits the HTTP boundary the Stimulus controller will call: a sequence of
# POST requests representing the user typing, switching voices, or
# changing source type. If the endpoint responds correctly to each of
# these, the Stimulus layer is a thin pass-through.
#
# Structural test for the Stimulus JS file itself lives at the bottom —
# the Implementer creates the file; this suite only asserts its presence.
class EpisodeCostPreviewFlowTest < ActionDispatch::IntegrationTest
  setup do
    @credit_user = users(:credit_user)
    @credit_user.update!(voice_preference: "felix")
    CreditBalance.for(@credit_user).update!(balance: 5)
    sign_in_as(@credit_user)
  end

  test "progressive text input reshapes cost from 1 to 2 as user crosses 20k boundary" do
    @credit_user.update!(voice_preference: "callum") # Premium

    # User types 5k chars — still 1 credit.
    post "/api/internal/episodes/cost_preview",
      params: { source_type: "paste", text: "A" * 5_000 },
      as: :json
    assert_response :success
    assert_equal 1, response.parsed_body["cost"]

    # User keeps typing to 20k — boundary, still 1 credit.
    post "/api/internal/episodes/cost_preview",
      params: { source_type: "paste", text: "A" * 20_000 },
      as: :json
    assert_response :success
    assert_equal 1, response.parsed_body["cost"]

    # User crosses 20k — now 2 credits.
    post "/api/internal/episodes/cost_preview",
      params: { source_type: "paste", text: "A" * 20_001 },
      as: :json
    assert_response :success
    assert_equal 2, response.parsed_body["cost"]
  end

  test "same length, flipping voice preference flips the cost" do
    long_text = "A" * 30_000

    @credit_user.update!(voice_preference: "felix") # Standard
    post "/api/internal/episodes/cost_preview",
      params: { source_type: "paste", text: long_text },
      as: :json
    assert_response :success
    assert_equal 1, response.parsed_body["cost"]
    assert_equal "standard", response.parsed_body["voice_tier"]

    @credit_user.update!(voice_preference: "callum") # Premium
    post "/api/internal/episodes/cost_preview",
      params: { source_type: "paste", text: long_text },
      as: :json
    assert_response :success
    assert_equal 2, response.parsed_body["cost"]
    assert_equal "premium", response.parsed_body["voice_tier"]
  end

  test "endpoint reachable from a logged-in session (cookie auth, same as browser)" do
    # This mirrors what a real browser hit looks like: signed cookie for
    # session_id set in setup, standard JSON content type, no API token.
    post "/api/internal/episodes/cost_preview",
      params: { source_type: "paste", text: "A" * 1_000 },
      as: :json

    assert_response :success
    body = response.parsed_body
    assert_kind_of Integer, body["cost"]
    assert_kind_of Integer, body["balance"]
    assert_includes [ true, false ], body["sufficient"]
    assert_includes %w[standard premium], body["voice_tier"]
  end

  test "switching source_type between calls does not leak state" do
    @credit_user.update!(voice_preference: "callum")

    # User on URL tab — cost is deferred (length unknown at preview time).
    # Brick 3 (agent-team-7i24) kills the source_type=='url' → 1 sentinel.
    # The endpoint now returns cost: nil for URL previews; the client is
    # expected to render a "cost shown after fetch" placeholder rather than
    # the misleading "1 credit" that under-prices Premium + >20k articles.
    post "/api/internal/episodes/cost_preview",
      params: { source_type: "url", url: "https://example.com/article" },
      as: :json
    assert_response :success
    assert_nil response.parsed_body["cost"],
      "URL preview must return cost: nil (deferred); client renders placeholder"

    # User switches to Paste with 25k chars — now 2 credits.
    post "/api/internal/episodes/cost_preview",
      params: { source_type: "paste", text: "A" * 25_000 },
      as: :json
    assert_response :success
    assert_equal 2, response.parsed_body["cost"]

    # User switches to Upload tab with 10k-byte file — back to 1 credit.
    post "/api/internal/episodes/cost_preview",
      params: { source_type: "upload", upload_length: 10_000 },
      as: :json
    assert_response :success
    assert_equal 1, response.parsed_body["cost"]
  end

  # --- URL cost-preview deferral (agent-team-7i24) ----------------------------
  #
  # Dedicated coverage for the sentinel-kill landing at the HTTP boundary.
  # A URL preview used to return cost: 1 — the Premium + >20k URL case
  # was silently mis-priced until ProcessesUrlEpisode re-computed cost.
  # The fix: return cost: nil at preview time; the client renders
  # "cost shown after fetch" and the true debit happens in the async job.

  test "URL source_type returns cost: nil (deferred), independent of voice tier" do
    @credit_user.update!(voice_preference: "callum") # Premium — matters most for URL
    post "/api/internal/episodes/cost_preview",
      params: { source_type: "url", url: "https://example.com/a-very-long-article" },
      as: :json

    assert_response :success
    body = response.parsed_body
    assert_nil body["cost"],
      "URL preview cost must be nil (deferred) — old sentinel '1' under-priced Premium + >20k URLs"
    assert_equal "premium", body["voice_tier"]
  end

  test "URL source_type with Standard voice also returns cost: nil" do
    @credit_user.update!(voice_preference: "felix") # Standard
    post "/api/internal/episodes/cost_preview",
      params: { source_type: "url", url: "https://example.com/short-article" },
      as: :json

    assert_response :success
    body = response.parsed_body
    assert_nil body["cost"],
      "URL preview cost must be nil regardless of voice tier"
    assert_equal "standard", body["voice_tier"]
  end

  # ---------- Structural: Stimulus controller file exists ----------
  #
  # No JS unit-test harness in the project. The Stimulus controller
  # behavior (debounce, event listeners) is verified manually; we only
  # assert the file exists so the import map / asset pipeline can load
  # it. If a JS test harness is added later, replace this with real
  # behavioral tests.

  test "cost_preview Stimulus controller file exists" do
    path = Rails.root.join("app/javascript/controllers/cost_preview_controller.js")
    assert File.exist?(path),
      "Expected Stimulus controller at #{path} — create this file as part of gq88 implementation"
  end

  # Structural check for B1 (tab-switch stale preview). The Stimulus layer
  # must reset the preview when the user switches between URL / Paste /
  # Upload tabs, otherwise a long-paste "2 credits" reading sticks around
  # on the URL tab where the real cost is always 1. Exercising this in an
  # HTTP-only integration suite is impossible — assert the wiring exists
  # at the source level instead.
  test "cost_preview controller subscribes to tab-switch:changed" do
    js_path = Rails.root.join("app/javascript/controllers/cost_preview_controller.js")
    source = File.read(js_path)
    assert_includes source, "tabChanged",
      "cost_preview_controller.js must define a tabChanged handler to reset preview on tab switch"

    view_path = Rails.root.join("app/views/episodes/new.html.erb")
    erb = File.read(view_path)
    assert_includes erb, "tab-switch:changed->cost-preview#tabChanged",
      "new.html.erb must wire the tab-switch:changed event to cost-preview#tabChanged"
  end

  test "tab_switch controller dispatches the :changed event" do
    js_path = Rails.root.join("app/javascript/controllers/tab_switch_controller.js")
    source = File.read(js_path)
    assert_includes source, 'this.dispatch("changed"',
      "tab_switch_controller.js must dispatch a :changed event so other controllers can react"
  end
end
