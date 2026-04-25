# frozen_string_literal: true

require "test_helper"

# Tests for the anonymous home page pricing section + FAQ copy after iny7.
#
# iny7 removes all user-facing subscription surfaces: the Monthly/Yearly
# pricing toggle goes away, the two Premium tiers ($9/mo, $89/yr) are
# replaced by three credit-pack tiers (Starter/Standard/Bulk), and the
# FAQ is rewritten to stop pitching a subscription.
class PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Anonymous; PagesController#home redirects authenticated users.
    get root_path
    assert_response :success
    @body = response.body
  end

  # --- Pricing section: no subscription surfaces ---

  test "home page does not render subscription prices" do
    refute_match "$9/month", @body
    refute_match "$89/year", @body
    refute_match "Premium Monthly", @body
    refute_match "Premium Annual", @body
  end

  test "home page does not render premium plan signup CTAs" do
    assert_select %([data-plan="premium_monthly"]), false,
      "Expected no data-plan=premium_monthly buttons on home page"
    assert_select %([data-plan="premium_annual"]), false,
      "Expected no data-plan=premium_annual buttons on home page"
  end

  test "home page does not render the monthly/annual pricing toggle" do
    assert_select %(input[name="frequency"]), false,
      "Expected no Monthly/Yearly frequency toggle on home page"
    # The pricing_toggle Stimulus controller wraps the toggle. If it's still
    # wired in, the subscription UX hasn't been removed.
    assert_select %([data-controller~="pricing-toggle"]), false,
      "Expected no pricing-toggle stimulus controller on home page"
    # The shared/marketing/pricing_hero_multi partial renders an <el-tab-group>
    # with Monthly/Yearly tab buttons. After iny7 there's one panel of tiers,
    # so the pricing-section tab-group must be absent.
    assert_select %(el-tab-group), false,
      "Expected no el-tab-group (Monthly/Yearly toggle) on home page"
  end

  test "home page forbids 'Get Premium' and 'Subscribe to' copy" do
    refute_includes @body, "Get Premium"
    refute_includes @body, "Subscribe to"
  end

  # --- Pricing section: three credit packs + Free ---

  test "home page renders Starter / Standard / Bulk pack labels" do
    assert_match "Starter", @body
    assert_match "Standard", @body
    assert_match "Bulk", @body
  end

  test "home page renders the three credit pack prices" do
    assert_match "$9.99", @body
    assert_match "$17.99", @body
    assert_match "$32.99", @body
  end

  test "home page renders three credit_pack CTAs with pack_size 5/10/20" do
    assert_select %([data-plan="credit_pack"][data-pack-size="5"]), 1,
      "Expected one credit_pack CTA for 5-pack (Starter)"
    assert_select %([data-plan="credit_pack"][data-pack-size="10"]), 1,
      "Expected one credit_pack CTA for 10-pack (Standard)"
    assert_select %([data-plan="credit_pack"][data-pack-size="20"]), 1,
      "Expected one credit_pack CTA for 20-pack (Bulk)"
  end

  test "home page marks the 20-pack Bulk card as Best value" do
    # Implementer may choose the exact element, but the 'Best value' badge
    # copy must appear somewhere in the pricing section adjacent to the
    # Bulk / $32.99 tier.
    assert_match "Best value", @body
  end

  test "home page still renders the Free tier with $0 / 2 episodes per month" do
    assert_match "$0", @body
    assert_match "2 episodes", @body
  end

  # --- FAQ: no subscription language ---

  test "home page FAQ does not pitch a $9/month subscription" do
    refute_match "$9/month", @body
    refute_match "subscription", @body
    refute_match "unlimited episodes", @body
  end

  test "home page FAQ mentions credit pack pricing" do
    assert_match "credit pack", @body
    # The Starter-pack entry-point price from the rewritten FAQ.
    assert_match "$9.99 for 5 episodes", @body
  end

  # --- Splitting Long Articles help page (agent-team-qc8o) -------------------
  #
  # Reached from the inline tip rendered on a failed-with-char-limit episode
  # card. The page walks users through the paste-and-split workaround.

  test "splitting articles help page renders successfully" do
    get help_splitting_articles_path
    assert_response :success
  end

  test "splitting articles help page mounts the scroll-spy controller" do
    get help_splitting_articles_path
    assert_select %([data-controller~="scroll-spy"])
    assert_select %([data-scroll-spy-target="step"]), 4,
      "Expected 4 step articles for the scroll-spy to observe"
    assert_select %([data-scroll-spy-target="link"]), 4,
      "Expected 4 nav links matching the 4 steps"
  end

  test "splitting articles help page links to the paste form deep-link" do
    get help_splitting_articles_path
    assert_select %(a[href="#{new_episode_path(source: "paste")}"])
  end

  test "splitting articles is reachable from the help nav" do
    get help_add_rss_feed_path
    assert_select %(a[href="#{help_splitting_articles_path}"])
  end
end
