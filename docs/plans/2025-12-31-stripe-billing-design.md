# Stripe Billing Integration Design

## Overview

Add Stripe subscription billing to upgrade free users to Premium tier. Users can upgrade from free to premium, downgrade back to free, and switch between monthly and annual billing.

## Key Decisions

- **Stripe Checkout + Customer Portal** — Checkout for upgrades, Portal for management (cancel, switch plans, update payment)
- **Subscription as source of truth** — User tier derived from subscription status, not stored on user
- **Re-fetch from Stripe API** — Webhooks trigger a fresh API call to get current state (pay gem pattern)
- **Keep canceled records** — Subscription records persist for history/analytics
- **Monthly upgrade nudge** — Email when free users hit their 2/2 episode limit

## Database Schema

### New `subscriptions` table

```ruby
create_table :subscriptions do |t|
  t.references :user, null: false, foreign_key: true, index: { unique: true }
  t.string :stripe_customer_id, null: false
  t.string :stripe_subscription_id, null: false
  t.string :stripe_price_id, null: false
  t.integer :status, null: false, default: 0
  t.datetime :current_period_end, null: false
  t.timestamps

  t.index :stripe_customer_id, unique: true
  t.index :stripe_subscription_id, unique: true
end
```

### Modify `users` table

```ruby
add_column :users, :account_type, :integer, default: 0, null: false
remove_column :users, :tier
```

### Models

```ruby
class Subscription < ApplicationRecord
  belongs_to :user

  enum :status, { active: 0, past_due: 1, canceled: 2 }
end

class User < ApplicationRecord
  has_one :subscription, dependent: :destroy

  enum :account_type, { standard: 0, complimentary: 1, unlimited: 2 }, default: :standard

  def premium?
    subscription&.active? || complimentary? || unlimited?
  end

  def free?
    standard? && !subscription&.active?
  end
end
```

### Account Types

| Type | Purpose |
|------|---------|
| `standard` | Regular user, tier from subscription |
| `complimentary` | Permanent free premium (friends/family) |
| `unlimited` | Admin/owner, no limits |

### Subscription Statuses

| Status | Meaning | User Access |
|--------|---------|-------------|
| `active` | Paid and current | Premium |
| `past_due` | Payment failed, retrying | Free (downgraded immediately) |
| `canceled` | Subscription ended | Free |

## Routes

```ruby
# Pricing section on landing page
get "pricing", to: redirect("/#pricing")

# Billing & checkout (authenticated)
get "billing", to: "billing#show"
post "billing/portal", to: "billing#portal"
post "checkout", to: "checkout#create"
get "checkout/success", to: "checkout#success"
get "checkout/cancel", to: "checkout#cancel"

# Webhook (verified by Stripe signature)
post "webhooks/stripe", to: "webhooks#stripe"
```

| Route | Purpose |
|-------|---------|
| `GET /pricing` | Redirects to `/#pricing` anchor on landing page |
| `GET /billing` | Shows subscription status, upgrade CTA for free users |
| `POST /billing/portal` | Creates Stripe Customer Portal session, redirects |
| `POST /checkout` | Creates Stripe Checkout session with selected price |
| `GET /checkout/success` | Post-payment confirmation page |
| `GET /checkout/cancel` | Redirect back to billing on abandoned checkout |
| `POST /webhooks/stripe` | Receives Stripe webhook events |

## Services

### Checkout Flow

| Service | Purpose |
|---------|---------|
| `CreatesCheckoutSession` | Creates Stripe Checkout session, returns URL |
| `CreatesBillingPortalSession` | Creates Stripe Customer Portal session, returns URL |

### Webhook Handlers

| Service | Purpose |
|---------|---------|
| `RoutesStripeWebhook` | Verifies signature, routes events to handlers |
| `CreatesSubscriptionFromCheckout` | Handles checkout.session.completed |
| `SyncsSubscription` | Syncs local state from Stripe subscription |

### Email

| Service | Purpose |
|---------|---------|
| `SendsUpgradeNudge` | Sends monthly email when free user hits 2/2 limit |

## Webhook Routing

```ruby
class RoutesStripeWebhook
  def self.call(event:)
    case event.type
    when "checkout.session.completed"
      CreatesSubscriptionFromCheckout.call(session: event.data.object)
    when "customer.subscription.updated"
      SyncsSubscription.call(stripe_subscription_id: event.data.object.id)
    when "customer.subscription.deleted"
      SyncsSubscription.call(stripe_subscription_id: event.data.object.id)
    when "invoice.payment_failed"
      SyncsSubscription.call(stripe_subscription_id: event.data.object.subscription)
    end
  end
end
```

## SyncsSubscription Service

Re-fetches from Stripe API to get authoritative state (inspired by pay gem pattern):

```ruby
class SyncsSubscription
  def self.call(stripe_subscription_id:)
    stripe_subscription = Stripe::Subscription.retrieve(stripe_subscription_id)

    subscription = Subscription.find_or_initialize_by(
      stripe_subscription_id: stripe_subscription.id
    )

    subscription.update!(
      user: find_user(stripe_subscription.customer),
      stripe_customer_id: stripe_subscription.customer,
      status: map_status(stripe_subscription.status),
      stripe_price_id: stripe_subscription.items.data.first.price.id,
      current_period_end: Time.at(stripe_subscription.current_period_end)
    )

    Result.success(subscription)
  rescue Stripe::StripeError => e
    Result.failure("Stripe API error: #{e.message}")
  end

  private_class_method def self.map_status(stripe_status)
    case stripe_status
    when "active", "trialing"
      :active
    when "past_due"
      :past_due
    else
      :canceled
    end
  end
end
```

## Payment Failure Handling

When payment fails:
1. Stripe sends `invoice.payment_failed` webhook
2. `SyncsSubscription` updates status to `past_due`
3. User is immediately downgraded (no grace period)
4. Banner shown: "Payment failed. Update payment method."
5. Stripe retries payment over ~2-3 weeks
6. If retry succeeds, `customer.subscription.updated` fires, status → `active`
7. If all retries fail, `customer.subscription.deleted` fires, status → `canceled`

## UI & Views

### Landing Page Pricing Section (`/#pricing`)

**Placement:** Between FAQ and Signup sections

**Layout:** Two cards side-by-side (stacked on mobile), max-width container matching existing sections.

**Header:**
```erb
<h2 class="text-2xl font-semibold tracking-tight sm:text-3xl">Pricing</h2>
<p class="mt-4 text-base/7 text-[var(--color-subtext)]">
  2 free episodes every month. Upgrade anytime for unlimited.
</p>
```

**Monthly/Annual Toggle:**
- CSS-only toggle using radio buttons
- Defaults to monthly
- Controls which price displays on Premium card
- Stimulus controller updates Premium button href when toggled

**Free Card:**
- Ring style: `ring-1 ring-[var(--color-overlay0)]` (subtle)
- Price: $0/month
- Button: "Create my feed" → `#signup` (outline style)
- Features:
  - Private podcast feed
  - Paste links, text, or upload files
  - Choose your voice
  - 2 episodes per month
  - Up to 15,000 characters

**Premium Card (featured):**
- Ring style: `ring-2 ring-[var(--color-primary)]` (emphasized)
- Badge: "Most popular"
- Price: $9/month or $89/year (toggles based on selection)
- Button: "Get Premium" → `#signup?plan=premium_monthly` or `#signup?plan=premium_annual` (solid style)
- Features:
  - Everything in Free, plus:
  - Unlimited episodes
  - Up to 50,000 characters

**Stimulus Controller:** `pricing_toggle_controller.js`
- Updates Premium button href when toggle changes
- `premium_monthly` ↔ `premium_annual`

**Post-Signup Flow:**
- Magic link preserves `plan` param
- After login with `plan=premium_*`, redirect to `/checkout?price_id=<matching_stripe_price>`
- Without `plan` param, redirect to dashboard (default)

### Billing Page (`/billing`)

| User State | Display |
|------------|---------|
| Free | Plan: Free. Usage: 1/2 episodes. Upgrade CTA with monthly/annual toggle |
| Premium (active) | Plan: Premium ($9/mo). Renews: Jan 15. "Manage Subscription" → Portal |
| Premium (past_due) | Banner: "Payment failed." Plan shown. "Fix Payment" → Portal |
| Premium (canceled) | "Subscription ended Dec 15. Resubscribe?" Upgrade CTA |
| Complimentary | Plan: Premium (complimentary). No billing actions |
| Unlimited | Plan: Unlimited. No limits shown |

### Contextual Upgrade Prompt

Shows when free user hits 2/2 limit:
- "You've used all 2 free episodes this month. Upgrade for unlimited."
- Link to billing page

## Email: Upgrade Nudge

Sent once per month when free user hits 2/2 episode limit.

**Subject:** "Ready for more?"

**Trigger:** In `RecordEpisodeUsage`, after incrementing to 2:
```ruby
if usage.episode_count == AppConfig::FREE_MONTHLY_EPISODES
  SendsUpgradeNudge.call(user: user)
end
```

Creates one `SentMessage` record per month (e.g., `upgrade_nudge_2025_01`) for analytics/history.

## Gifting Premium Access

### Friends/Family (permanent)

Set `account_type: :complimentary` on user. Premium forever, no Stripe involved.

### Potential Customers (converts to paid)

Use Stripe coupons:
1. Create coupon: "100% off for 3 months"
2. Create promotion code (e.g., `FRIEND3MO`)
3. User goes through checkout with code → $0 charge
4. After 3 months, Stripe charges full price (or they cancel)

## Configuration

### Secrets Management

**Source of truth:** 1Password

**Deploy flow:**
1. Store secrets in 1Password
2. Sync to Google Cloud Secret Manager:
   ```bash
   op read "op://Private/Stripe TTS/secret_key" | gcloud secrets versions add stripe-secret-key --data-file=-
   ```
3. GitHub Actions fetches from Secret Manager
4. Kamal injects as env vars at runtime

**Secrets required:**
- `STRIPE_SECRET_KEY`
- `STRIPE_PUBLISHABLE_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_ID_MONTHLY`
- `STRIPE_PRICE_ID_ANNUAL`

### Stripe Dashboard Setup

1. Create Product: "Very Normal TTS Premium"
2. Create Prices: $9/month, $89/year
3. Configure Customer Portal (allow cancel, plan switching)
4. Add webhook endpoint: `https://tts.verynormal.dev/webhooks/stripe`
5. Subscribe to events:
   - `checkout.session.completed`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_failed`

## Local Development & Testing

### Stripe CLI

```bash
# Install
brew install stripe/stripe-cli/stripe

# Forward webhooks to local server
stripe listen --forward-to localhost:3000/webhooks/stripe

# Trigger test events
stripe trigger checkout.session.completed
```

### Test Cards

| Card | Result |
|------|--------|
| `4242424242424242` | Success |
| `4000000000000341` | Decline |
| `4000002500003155` | Requires 3DS |
