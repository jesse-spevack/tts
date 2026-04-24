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

    assert_redirected_to login_path(return_to: "/settings")
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

  # --- Email confirmation toggle accessibility (agent-team-wk6) ---
  #
  # Hand-rolled toggle in app/views/settings/show.html.erb. Must be announced
  # as a switch to screen readers and must respect prefers-reduced-motion.

  test "email confirmation toggle has role=switch and aria-checked reflecting state (on)" do
    EnablesEmailEpisodes.call(user: @user)
    @user.update!(email_episode_confirmation: true)

    get settings_path

    assert_response :success
    assert_select "section#email input[type=checkbox][name=email_episode_confirmation][role=switch][aria-checked=true]"
  end

  test "email confirmation toggle has aria-checked=false when preference is off" do
    EnablesEmailEpisodes.call(user: @user)
    @user.update!(email_episode_confirmation: false)

    get settings_path

    assert_response :success
    assert_select "section#email input[type=checkbox][name=email_episode_confirmation][role=switch][aria-checked=false]"
  end

  test "email confirmation toggle respects prefers-reduced-motion" do
    EnablesEmailEpisodes.call(user: @user)

    get settings_path

    assert_response :success
    # Tailwind's motion-safe: variant gates the transition on users without
    # prefers-reduced-motion: reduce. Presence on the track is enough to
    # guarantee reduced-motion users don't get the slide animation.
    assert_select "section#email span.motion-safe\\:transition-colors"
    assert_select "section#email span.motion-safe\\:after\\:transition-transform"
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

  # --- Connected Apps: app identity (agent-team-3d9) ---
  #
  # Connected Apps rows must render a size-9 rounded-lg badge per connected app
  # (logo for known apps, initials fallback otherwise) and an absolute-timestamp
  # tooltip on the "Connected X ago" text. No oauth_applications / oauth_access_tokens
  # fixtures exist, so records are created inline — matches the pattern in
  # test/controllers/settings/connected_apps_controller_test.rb.

  test "show renders badge for each connected app" do
    app = Doorkeeper::Application.create!(
      name: "Claude",
      uid: "test_claude_3d9_badge",
      redirect_uri: "http://localhost:3001/callback",
      scopes: "podread",
      confidential: false
    )
    Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )

    get settings_path

    assert_response :success
    assert_select "section#connected-apps span.size-9.rounded-lg", count: 1
  end

  test "show renders absolute timestamp tooltip on Connected X ago" do
    app = Doorkeeper::Application.create!(
      name: "Claude",
      uid: "test_claude_3d9_tooltip",
      redirect_uri: "http://localhost:3001/callback",
      scopes: "podread",
      confidential: false
    )
    Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: @user.id,
      scopes: "podread",
      expires_in: 1.hour
    )

    get settings_path

    assert_response :success
    # Option-2 tooltip: <time> element with datetime, title, aria-label.
    assert_select "section#connected-apps time[title][datetime][aria-label]" do |elements|
      assert_equal 1, elements.length
      title = elements.first["title"]
      assert_match(/\A[A-Z][a-z]+ \d{1,2}, \d{4} at \d{1,2}:\d{2} [AP]M\z/, title)
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

  # --- Credits section ---
  #
  # New <section id="credits"> between Billing and Browser Extension.
  # Visibility: show when has_credits? || !premium?; hide when premium? && !has_credits?.
  # Three render paths:
  #   - has_credits? (any tier): balance + "Buy More Credits" form POST /checkout.
  #   - subscription&.canceled? (no credits): grace branch — "Your subscription ended on <date>"
  #     + softened "Pay-as-you-go is available..." + "Buy Credit Pack" CTA.
  #   - !premium? && !has_credits? (free, never bought): empty-state acquisition card
  #     with "Buy Credit Pack" CTA.

  test "credits card renders for credit_user with balance and Buy More Credits CTA" do
    sign_in_as(users(:credit_user))
    balance = credit_balances(:with_credits).balance # 3

    get settings_path

    assert_response :success
    assert_select "section#credits", count: 1
    assert_select "section#credits h2", text: /Credits/
    assert_select "section#credits" do
      assert_select "*", text: /#{balance}/
      assert_select "form[action=?][method=?]", checkout_path, "post" do
        assert_select "input[type=hidden][name='pack_size'][value='5']"
        assert_select "input[type=submit][value=?]", "Buy More Credits"
      end
    end
  end

  test "credits card renders empty-state for free user (no subscription, no credits)" do
    # @user is users(:one) — standard, no subscription, no credit_balance (free).
    get settings_path

    assert_response :success
    assert_select "section#credits", count: 1
    assert_select "section#credits h2", text: /Credits/
    assert_select "section#credits" do
      # Empty-state copy — loose match on any of the expected phrases.
      assert_select "*", text: /Pay as you go|no subscription required/i
      assert_select "input[type=submit][value=?]", "Buy Credit Pack"
      # "credits remaining" phrasing belongs to the has_credits? path only.
      assert_select "*", text: /credits remaining/, count: 0
    end
  end

  test "credits card does NOT render for premium subscriber with zero credits" do
    # users(:subscriber) has active_subscription fixture — premium? = true, has_credits? = false.
    sign_in_as(users(:subscriber))

    get settings_path

    assert_response :success
    assert_select "section#credits", count: 0
    # Sanity: Billing card still renders for this premium user.
    assert_select "section#billing"
  end

  test "credits card renders for premium user with leftover credits (rollover case)" do
    # Premium + credits > 0 — covers the "bought pack, then subscribed" edge case.
    user = users(:annual_subscriber)
    CreditBalance.for(user).add!(3)
    sign_in_as(user)

    get settings_path

    assert_response :success
    assert_select "section#credits", count: 1
    assert_select "section#credits" do
      assert_select "*", text: /3/
      assert_select "input[type=submit][value=?]", "Buy More Credits"
    end
  end

  test "credits card pluralizes 'episode credit' for balance of 1" do
    user = users(:credit_user)
    user.credit_balance.update!(balance: 1)
    sign_in_as(user)

    get settings_path

    assert_response :success
    assert_select "section#credits *", text: /1 episode credit\b/
    # Plural form must NOT appear for a balance of 1.
    assert_select "section#credits *", text: /1 episode credits/, count: 0
  end

  test "credits card renders grace branch for canceled subscriber with zero credits" do
    user = users(:canceled_subscriber)
    sign_in_as(user)
    expected_date = subscriptions(:canceled_subscription).current_period_end.strftime("%B %-d, %Y")

    get settings_path

    assert_response :success
    assert_select "section#credits", count: 1
    assert_select "section#credits" do
      assert_select "*", text: /Your subscription ended on #{Regexp.escape(expected_date)}/
      assert_select "*", text: /Pay-as-you-go is available/i
      assert_select "input[type=submit][value=?]", "Buy Credit Pack"
      # Must NOT show the default empty-state marketing phrasing.
      assert_select "*", text: /no subscription required/, count: 0
      # Must NOT show the has_credits? branch.
      assert_select "*", text: /credits remaining/, count: 0
    end
  end

  test "credits card renders empty-state for past-due subscriber (A1 — grace-period alt path)" do
    # Past-due sub is in Stripe's dunning grace (status=1, retrying payment).
    # premium? returns false, so user falls into the empty-state branch by design.
    # Lock this in explicitly so it doesn't drift.
    sign_in_as(users(:past_due_subscriber))

    get settings_path

    assert_response :success
    assert_select "section#credits", count: 1
    assert_select "section#credits" do
      assert_select "*", text: /Pay as you go|no subscription required/i
      assert_select "input[type=submit][value=?]", "Buy Credit Pack"
    end
  end

  test "credits card does NOT render for complimentary user with zero credits" do
    # Complimentary users are premium? = true → card hides unless they have credits.
    sign_in_as(users(:complimentary_user))

    get settings_path

    assert_response :success
    assert_select "section#credits", count: 0
  end

  test "credits card does NOT render for unlimited user with zero credits" do
    # Unlimited users are premium? = true → card hides unless they have credits.
    sign_in_as(users(:unlimited_user))

    get settings_path

    assert_response :success
    assert_select "section#credits", count: 0
  end

  # --- Three-pack credit purchase UI (agent-team-qc7t) ---
  #
  # Empty-state credits section now renders three pack cards (Starter 5 /
  # Standard 10 / Bulk 20) instead of a single pack. The 20-pack is highlighted
  # with a "Best Value" badge. Each card has its own form posting to
  # /checkout with the appropriate pack_size.

  test "credits empty-state renders all three pack labels" do
    # @user is users(:one) — free, no credits → empty-state branch.
    get settings_path

    assert_response :success
    assert_select "section#credits" do
      assert_select "*", text: /Starter/
      assert_select "*", text: /Standard/
      assert_select "*", text: /Bulk/
    end
  end

  test "credits empty-state renders all three pack prices" do
    get settings_path

    assert_response :success
    assert_select "section#credits" do
      assert_select "*", text: /\$9\.99/
      assert_select "*", text: /\$17\.99/
      assert_select "*", text: /\$32\.99/
    end
  end

  test "credits empty-state renders three checkout forms, one per pack_size" do
    get settings_path

    assert_response :success
    assert_select "section#credits" do
      assert_select "form[action=?][method=?]", checkout_path, "post" do
        assert_select "input[type=hidden][name='pack_size'][value='5']"
      end
      assert_select "form[action=?][method=?]", checkout_path, "post" do
        assert_select "input[type=hidden][name='pack_size'][value='10']"
      end
      assert_select "form[action=?][method=?]", checkout_path, "post" do
        assert_select "input[type=hidden][name='pack_size'][value='20']"
      end
    end
  end

  test "credits empty-state flags the 20-pack with a Best Value badge" do
    get settings_path

    assert_response :success
    assert_select "section#credits" do
      assert_select "*", text: /Best Value/i
    end
  end

  # --- Demo Mode relocated to /admin (agent-team-pte) ---
  #
  # Demo Mode toggle moved out of /settings to /admin/demo_mode. The /settings
  # page should no longer render the toggle block or nav entries, even for admins.

  test "settings page does not render Demo Mode block for admin users" do
    sign_in_as(users(:admin_user))

    get settings_path

    assert_response :success
    assert_select "section#demo", count: 0
    assert_select "h2", text: "Demo Mode", count: 0
    assert_select "a[href='#demo']", count: 0
  end

  test "settings page renders Account section with email and Delete account link" do
    get settings_path

    assert_response :success
    assert_select "section#account" do
      assert_select "h2", text: "Account"
      assert_select "*", text: /#{Regexp.escape(@user.email_address)}/
      assert_select "a[href=?]", new_settings_account_deletion_path, text: "Delete account"
    end
  end
end
