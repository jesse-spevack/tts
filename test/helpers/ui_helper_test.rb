# frozen_string_literal: true

require "test_helper"

class UiHelperTest < ActionView::TestCase
  include UiHelper

  # --- status_pill_label ---

  test "status_pill_label returns 'Active' for active subscription" do
    assert_equal "Active", status_pill_label(subscriptions(:active_subscription))
  end

  test "status_pill_label returns 'Canceling' for active subscription with cancel_at" do
    assert_equal "Canceling", status_pill_label(subscriptions(:canceling_subscription))
  end

  test "status_pill_label returns 'Past Due' for past_due subscription" do
    assert_equal "Past Due", status_pill_label(subscriptions(:past_due_subscription))
  end

  test "status_pill_label returns 'Canceled' for canceled subscription" do
    assert_equal "Canceled", status_pill_label(subscriptions(:canceled_subscription))
  end

  test "status_pill_label returns empty string for nil subscription" do
    assert_equal "", status_pill_label(nil)
  end

  # --- status_pill_classes ---

  test "status_pill_classes returns green classes for active subscription" do
    assert_equal(
      "bg-green-50 text-green-700 dark:bg-green-500/10 dark:text-green-400",
      status_pill_classes(subscriptions(:active_subscription))
    )
  end

  test "status_pill_classes returns yellow classes for canceling subscription" do
    assert_equal(
      "bg-yellow-50 text-yellow-700 dark:bg-yellow-500/10 dark:text-yellow-400",
      status_pill_classes(subscriptions(:canceling_subscription))
    )
  end

  test "status_pill_classes returns yellow classes for past_due subscription" do
    assert_equal(
      "bg-yellow-50 text-yellow-700 dark:bg-yellow-500/10 dark:text-yellow-400",
      status_pill_classes(subscriptions(:past_due_subscription))
    )
  end

  test "status_pill_classes returns mist classes for canceled subscription" do
    assert_equal(
      "bg-mist-100 text-mist-600 dark:bg-mist-500/10 dark:text-mist-400",
      status_pill_classes(subscriptions(:canceled_subscription))
    )
  end

  test "status_pill_classes returns empty string for nil subscription" do
    assert_equal "", status_pill_classes(nil)
  end

  # --- manage_billing_cta_label ---

  test "manage_billing_cta_label returns 'Manage Billing' for active subscription" do
    assert_equal "Manage Billing", manage_billing_cta_label(subscriptions(:active_subscription))
  end

  test "manage_billing_cta_label returns 'Manage Billing' for canceling subscription" do
    assert_equal "Manage Billing", manage_billing_cta_label(subscriptions(:canceling_subscription))
  end

  test "manage_billing_cta_label returns 'Manage Billing' for past_due subscription" do
    assert_equal "Manage Billing", manage_billing_cta_label(subscriptions(:past_due_subscription))
  end

  test "manage_billing_cta_label returns 'Resubscribe' for canceled subscription" do
    assert_equal "Resubscribe", manage_billing_cta_label(subscriptions(:canceled_subscription))
  end

  test "manage_billing_cta_label returns 'Manage Billing' for nil subscription" do
    assert_equal "Manage Billing", manage_billing_cta_label(nil)
  end

  # --- credits_card_variant ---
  #
  # Drives the Credits section on /settings. Returns:
  #   :balance       — user has credits (any tier); show balance + "Buy More Credits".
  #   :canceled_grace — !premium, 0 credits, most recent subscription is canceled.
  #   :empty_state   — !premium, 0 credits, no canceled subscription (free user, including past_due).
  #   nil            — hide the card entirely (premium with 0 credits).

  test "credits_card_variant returns :balance for user with credits" do
    assert_equal :balance, credits_card_variant(users(:credit_user))
  end

  test "credits_card_variant returns :balance for premium user with rollover credits" do
    user = users(:annual_subscriber)
    CreditBalance.for(user).add!(3)
    assert_equal :balance, credits_card_variant(user)
  end

  test "credits_card_variant returns nil for premium subscriber with zero credits" do
    assert_nil credits_card_variant(users(:subscriber))
  end

  test "credits_card_variant returns nil for complimentary user with zero credits" do
    assert_nil credits_card_variant(users(:complimentary_user))
  end

  test "credits_card_variant returns nil for unlimited user with zero credits" do
    assert_nil credits_card_variant(users(:unlimited_user))
  end

  test "credits_card_variant returns :canceled_grace for canceled subscriber with zero credits" do
    assert_equal :canceled_grace, credits_card_variant(users(:canceled_subscriber))
  end

  test "credits_card_variant returns :empty_state for free user (never subscribed)" do
    assert_equal :empty_state, credits_card_variant(users(:one))
  end

  test "credits_card_variant returns :empty_state for past-due subscriber (A1 — grace-period alt path)" do
    # Past-due is Stripe dunning; premium? = false, subscription.canceled? = false → empty_state.
    assert_equal :empty_state, credits_card_variant(users(:past_due_subscriber))
  end

  # --- show_billing_section? (agent-team-01q.3) ---
  #
  # Gate for the /settings Billing card + section nav links. Returns true when
  # the user is premium (show ongoing subscription management) OR has any
  # subscription on file (canceled / past_due users still need access to the
  # Manage Billing CTA). Returns false only when both are absent.

  test "show_billing_section? returns true when user is premium and subscription is nil" do
    user = Struct.new(:premium?).new(true)
    assert show_billing_section?(user, nil)
  end

  test "show_billing_section? returns true when user is premium and subscription is present" do
    user = Struct.new(:premium?).new(true)
    subscription = Object.new
    assert show_billing_section?(user, subscription)
  end

  test "show_billing_section? returns true when user is not premium but subscription is present" do
    user = Struct.new(:premium?).new(false)
    subscription = Object.new
    assert show_billing_section?(user, subscription)
  end

  test "show_billing_section? returns false when user is not premium and subscription is nil" do
    user = Struct.new(:premium?).new(false)
    assert_not show_billing_section?(user, nil)
  end

  # --- oauth_app_badge (agent-team-3d9) ---
  #
  # Badge is a size-9 rounded-lg container that renders either:
  #   - an inlined SVG logo (when app/assets/images/oauth_apps/<slug>.svg exists), or
  #   - an initials fallback (first letter of each word, max 2, uppercased).
  # Known apps' SVGs use fill="currentColor" so the container's text color controls
  # theming in both light/dark. Unknown apps get a framed initials block.

  test "oauth_app_badge returns logo badge with inline SVG for known app (Claude)" do
    app = Struct.new(:name).new("Claude")
    html = oauth_app_badge(app)

    assert_includes html, "inline-flex"
    assert_includes html, "size-9"
    assert_includes html, "items-center"
    assert_includes html, "justify-center"
    assert_includes html, "rounded-lg"
    assert_includes html, "<svg"
    assert_includes html, 'fill="currentColor"'
    assert_includes html, "text-mist-950"
    assert_includes html, "dark:text-white"
  end

  test "oauth_app_badge returns logo badge with inline SVG for known app (ChatGPT)" do
    app = Struct.new(:name).new("ChatGPT")
    html = oauth_app_badge(app)

    assert_includes html, "inline-flex"
    assert_includes html, "size-9"
    assert_includes html, "items-center"
    assert_includes html, "justify-center"
    assert_includes html, "rounded-lg"
    assert_includes html, "<svg"
    assert_includes html, 'fill="currentColor"'
    assert_includes html, "text-mist-950"
    assert_includes html, "dark:text-white"
  end

  test "oauth_app_badge returns initials badge for unknown multi-word app" do
    app = Struct.new(:name).new("MCP Client")
    html = oauth_app_badge(app)

    assert_includes html, "MC"
    assert_includes html, "bg-mist-100"
    assert_includes html, "text-mist-700"
    assert_includes html, "dark:bg-mist-700"
    assert_includes html, "dark:text-mist-200"
    assert_includes html, "text-xs"
    assert_includes html, "font-semibold"
    assert_includes html, "size-9"
    assert_includes html, "rounded-lg"
    refute_includes html, "<svg"
  end

  test "oauth_app_badge returns single-letter initial for single-word unknown app" do
    app = Struct.new(:name).new("Slack")
    html = oauth_app_badge(app)

    assert_includes html, ">S<"
    refute_includes html, "<svg"
  end

  test "oauth_app_badge caps initials at two letters for three-word unknown app" do
    app = Struct.new(:name).new("Some Cool App")
    html = oauth_app_badge(app)

    assert_includes html, "SC"
    refute_includes html, "SCA"
    refute_includes html, "<svg"
  end

  test "oauth_app_badge resolves logo via app.name.parameterize (case-insensitive)" do
    app = Struct.new(:name).new("claude")
    html = oauth_app_badge(app)

    # Lowercase "claude" parameterizes to "claude" — should hit claude.svg
    # just like the "Claude" test above. Locks in that the helper doesn't
    # do a raw case-sensitive filename match.
    assert_includes html, "<svg"
    assert_includes html, 'fill="currentColor"'
  end

  test "oauth_app_badge strips leading/trailing whitespace before computing initials" do
    app = Struct.new(:name).new("  Foo Bar  ")
    html = oauth_app_badge(app)
    assert_includes html, "FB"
    refute_includes html, ">F<"
  end

  test "oauth_app_badge merges size-7 with any pre-existing class on the root svg" do
    require "tempfile"
    stub_name = "merge-test-#{SecureRandom.hex(4)}"
    stub_path = Rails.root.join("app/assets/images/oauth_apps/#{stub_name}.svg")
    stub_path.write(%(<svg xmlns="http://www.w3.org/2000/svg" class="existing-class" viewBox="0 0 10 10"><path d="M0 0h10v10H0z"/></svg>))
    begin
      app = Struct.new(:name).new(stub_name)
      html = oauth_app_badge(app)
      assert_match %r{<svg[^>]*class="[^"]*existing-class[^"]*"}, html
      assert_match %r{<svg[^>]*class="[^"]*size-7[^"]*"}, html
      # The merged class attribute should appear exactly once on the <svg>.
      svg_open_tag = html[/<svg\b[^>]*>/]
      assert_equal 1, svg_open_tag.scan(/\bclass=/).size,
        "expected exactly one class attribute on <svg>, got: #{svg_open_tag}"
    ensure
      stub_path.delete if stub_path.exist?
    end
  end
end
