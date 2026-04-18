# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(account_type: :standard)
    sign_in_as(@user)
    ENV["GOOGLE_CLOUD_BUCKET"] = "test-bucket"
  end

  test "show renders settings page" do
    get settings_path

    assert_response :success
    assert_select "h1", "Settings"
  end

  test "show displays available voices for free tier" do
    get settings_path

    assert_response :success
    assert_select "input[name='voice'][value='wren']"
    assert_select "input[name='voice'][value='felix']"
    assert_select "input[name='voice'][value='sloane']"
    assert_select "input[name='voice'][value='archer']"
    assert_select "input[name='voice'][value='elara']", count: 0
  end

  test "show displays all voices for unlimited tier" do
    @user.update!(account_type: :unlimited)
    get settings_path

    assert_response :success
    assert_select "input[name='voice'][value='wren']"
    assert_select "input[name='voice'][value='elara']"
  end

  test "show marks current voice_preference as selected" do
    @user.update!(voice_preference: "sloane")
    get settings_path

    assert_select "input[name='voice'][value='sloane'][checked]"
  end

  test "update saves valid voice_preference" do
    patch settings_path, params: { voice: "felix" }

    assert_redirected_to settings_path
    assert_equal "Settings saved.", flash[:notice]
    assert_equal "felix", @user.reload.voice_preference
  end

  test "update rejects invalid voice" do
    patch settings_path, params: { voice: "invalid" }

    assert_redirected_to settings_path
    assert_equal "Invalid voice selection.", flash[:alert]
  end

  test "update rejects chirp voice for free tier" do
    patch settings_path, params: { voice: "elara" }

    assert_redirected_to settings_path
    assert_equal "Invalid voice selection.", flash[:alert]
  end

  test "update allows chirp voice for unlimited tier" do
    @user.update!(account_type: :unlimited)
    patch settings_path, params: { voice: "elara" }

    assert_redirected_to settings_path
    assert_equal "Settings saved.", flash[:notice]
    assert_equal "elara", @user.reload.voice_preference
  end

  test "requires authentication" do
    sign_out
    get settings_path

    assert_redirected_to root_path
  end

  test "show displays email episodes section when disabled" do
    get settings_path

    assert_response :success
    assert_select "h2", text: "Email to Podcast"
    assert_select "button", text: "Enable Email Episodes"
  end

  test "show displays email ingest address when enabled" do
    EnablesEmailEpisodes.call(user: @user)

    get settings_path

    assert_response :success
    assert_select "code", text: @user.email_ingest_address
    assert_select "button", text: "Disable"
    assert_select "button", text: "Regenerate Address"
  end

  test "update saves email_episode_confirmation preference" do
    @user.update!(email_episode_confirmation: true)

    patch settings_path, params: { email_episode_confirmation: "0" }

    assert_redirected_to settings_path
    refute @user.reload.email_episode_confirmation?
  end

  test "update enables email_episode_confirmation" do
    @user.update!(email_episode_confirmation: false)

    patch settings_path, params: { email_episode_confirmation: "1" }

    assert_redirected_to settings_path
    assert @user.reload.email_episode_confirmation?
  end

  # --- Billing card: inline plan + renewal + price (agent-team-bwz) ---
  #
  # Card only renders for premium users (Current.user.premium? — active sub,
  # complimentary, or unlimited). Gate behavior is preserved for non-premium.
  # We assert on the #billing section to keep selectors scoped.

  test "billing card is not rendered for non-premium user" do
    # @user is standard with no subscription — free tier
    get settings_path

    assert_response :success
    assert_select "section#billing", count: 0
  end

  test "billing card renders for active monthly subscriber with plan, price, renewal, and Active pill" do
    sign_in_as(users(:subscriber))
    subscription = subscriptions(:active_subscription)
    expected_date = subscription.current_period_end.strftime("%B %-d, %Y")

    get settings_path

    assert_response :success
    assert_select "section#billing" do
      assert_select "*", text: /Premium Monthly/
      assert_select "*", text: /\$9\/mo/
      assert_select "*", text: /#{Regexp.escape(expected_date)}/
      # Active subs show "Renews" (not "Ends")
      assert_select "*", text: /Renews/
      # Active pill — green classes from billing/show.html.erb precedent
      assert_select "span.bg-green-50.text-green-700", text: /Active/
      # Manage Billing button still renders
      assert_select "a", text: "Manage Billing"
    end
  end

  test "billing card renders Premium Annual + $89/yr for annual subscriber" do
    sign_in_as(users(:annual_subscriber))

    get settings_path

    assert_response :success
    assert_select "section#billing" do
      assert_select "*", text: /Premium Annual/
      assert_select "*", text: /\$89\/yr/
      assert_select "*", text: /Renews/
      assert_select "span.bg-green-50.text-green-700", text: /Active/
      assert_select "a", text: "Manage Billing"
    end
  end

  test "billing card renders Canceling pill with yellow classes, Ends copy, and cancel_at date" do
    sign_in_as(users(:canceling_subscriber))
    subscription = subscriptions(:canceling_subscription)
    expected_date = subscription.cancel_at.strftime("%B %-d, %Y")

    get settings_path

    assert_response :success
    assert_select "section#billing" do
      # Yellow pill — existing canceling pattern uses yellow-50/yellow-700
      assert_select "span.bg-yellow-50.text-yellow-700", text: /Canceling/
      # Canceling subs show "Ends" (not "Renews") — semantic correctness (R1)
      assert_select "*", text: /Ends/
      assert_select "*", text: /Renews/, count: 0
      # Date shown is cancel_at, not current_period_end
      assert_select "*", text: /#{Regexp.escape(expected_date)}/
      assert_select "a", text: "Manage Billing"
    end
  end

  test "billing card renders Past Due pill with yellow classes for past_due subscriber" do
    sign_in_as(users(:past_due_subscriber))

    get settings_path

    # Gate widened (W2): card renders whenever Current.user.subscription.present?,
    # not just when premium?. past_due subs are NOT premium? (active? is false)
    # but MUST still surface on /settings so users can fix payment.
    assert_response :success
    assert_select "section#billing" do
      assert_select "span.bg-yellow-50.text-yellow-700", text: /Past Due/
      assert_select "a", text: "Manage Billing"
    end
  end

  test "billing card renders Canceled pill and hides renewal line for canceled subscriber" do
    sign_in_as(users(:canceled_subscriber))

    get settings_path

    # Gate widened (W2): canceled subscriptions still render the Billing card.
    # Renewal-line decision (option a): HIDE the "Renews {date}" line for canceled
    # subs — a canceled sub will not renew, and the "Canceled" pill already conveys
    # status. Historical plan name is kept for context. /billing handles the full
    # "ended on" narrative; /settings stays terse.
    # CTA label switches to "Resubscribe" since /billing's canceled branch shows
    # a Resubscribe section, not a portal button.
    assert_response :success
    assert_select "section#billing" do
      # Canceled pill uses mist classes per billing/show.html.erb precedent
      assert_select "span.bg-mist-100.text-mist-600", text: /Canceled/
      # Plan name still rendered for historical context
      assert_select "*", text: /Premium Monthly/
      # Button re-labeled to Resubscribe for canceled subs
      assert_select "a", text: "Resubscribe"
      assert_select "a", text: "Manage Billing", count: 0
      # No "Renews" or "Ends" copy should leak in for a canceled sub
      assert_select "*", text: /Renews/, count: 0
      assert_select "*", text: /Ends on/, count: 0
    end
  end

  test "billing card renders for complimentary user with Manage Billing button and no plan data" do
    sign_in_as(users(:complimentary_user))

    get settings_path

    # Complimentary users are premium? = true but have no subscription row.
    # Card should render (preserves pre-bwz behavior) with just the Manage Billing
    # button — no plan name, no pill, no renewal line.
    assert_response :success
    assert_select "section#billing" do
      assert_select "a", text: "Manage Billing"
      assert_select "*", text: /Premium Monthly/, count: 0
      assert_select "*", text: /Premium Annual/, count: 0
      assert_select "span.bg-green-50.text-green-700", count: 0
      assert_select "*", text: /Renews/, count: 0
      assert_select "*", text: /Ends/, count: 0
    end
  end

  test "billing card renders for unlimited user with Manage Billing button and no plan data" do
    sign_in_as(users(:unlimited_user))

    get settings_path

    # Same as complimentary: unlimited users are premium? = true but subscription-less.
    assert_response :success
    assert_select "section#billing" do
      assert_select "a", text: "Manage Billing"
      assert_select "*", text: /Premium Monthly/, count: 0
      assert_select "*", text: /Premium Annual/, count: 0
      assert_select "span.bg-green-50.text-green-700", count: 0
      assert_select "*", text: /Renews/, count: 0
      assert_select "*", text: /Ends/, count: 0
    end
  end

  test "billing card renders safely for subscription with unknown stripe_price_id" do
    # S8: future price rotation must not 500 /settings.
    user = users(:subscriber)
    subscription = subscriptions(:active_subscription)
    subscription.update_column(:stripe_price_id, "price_orphan_not_in_plan_info")
    sign_in_as(user)

    get settings_path

    assert_response :success
    assert_select "section#billing" do
      # Pill still renders even with unknown price
      assert_select "span.bg-green-50.text-green-700", text: /Active/
      # plan_name / plan_display_price are nil — no known plan text rendered
      assert_select "*", text: /Premium Monthly/, count: 0
      assert_select "*", text: /\$9\/mo/, count: 0
    end
  end
end
