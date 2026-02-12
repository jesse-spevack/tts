# Pay-As-You-Go Pricing Proposal

**Date:** February 2026
**Status:** Draft for Review

---

## Executive Summary

This proposal evaluates adding pay-as-you-go (PAYG) pricing to PodRead alongside the existing $9/month subscription. After analyzing our cost structure, user behavior, and implementation complexity, **the recommendation is to add a lightweight credit-based PAYG option alongside the existing subscription** — not to replace it.

---

## Current State

### Pricing Tiers

| Tier | Price | Episodes/Month | Character Limit |
|------|-------|----------------|-----------------|
| Free | $0 | 2 | 15,000 chars |
| Premium (Monthly) | $9/month | Unlimited | 50,000 chars |
| Premium (Annual) | $89/year (~$7.42/mo) | Unlimited | 50,000 chars |

### Per-Episode Cost to Us

| Component | Free Tier (15K chars) | Premium (50K chars) | Notes |
|-----------|-----------------------|---------------------|-------|
| Google Cloud TTS | ~$0.06 | ~$0.20 | $4 per 1M characters |
| Vertex AI (Gemini) | ~$0.002 | ~$0.005 | Content processing |
| Cloud Storage | ~$0.0001 | ~$0.0005 | Audio + RSS hosting |
| Stripe fee (amortized) | — | ~$0.02 | 2.9% + $0.30 per txn |
| **Total COGS per episode** | **~$0.06** | **~$0.23** | Excludes infra overhead |

### Subscription Margin Analysis

A Premium subscriber at $9/month:

| Episodes/Month | Total COGS | Gross Margin | Margin % |
|----------------|------------|--------------|----------|
| 5 | $1.15 | $7.85 | 87% |
| 10 | $2.30 | $6.70 | 74% |
| 20 | $4.60 | $4.40 | 49% |
| 40 | $9.20 | -$0.20 | -2% |

Break-even: ~39 episodes/month at 50K chars each.

---

## Proposed PAYG Pricing Options

### Option A: Per-Episode Flat Rate

Simple, predictable pricing. One flat fee per episode regardless of length (capped at 50K characters).

| Price Per Episode | Our COGS (avg) | Gross Margin | Margin % |
|-------------------|----------------|--------------|----------|
| $0.49 | $0.23 | $0.26 | 53% |
| $0.99 | $0.23 | $0.76 | 77% |
| $1.49 | $0.23 | $1.26 | 85% |
| $1.99 | $0.23 | $1.76 | 88% |

**Recommended: $0.99/episode.** This is psychologically clean, delivers 77% margin, and a user converting 10+ episodes/month has clear incentive to upgrade to the $9 subscription.

### Option B: Credit Packs (Pre-Paid Bundles)

Users buy episode credits in advance. Reduces per-transaction Stripe fees and creates commitment.

| Pack | Price | Per-Episode | Our COGS | Margin % | Stripe Fee Impact |
|------|-------|-------------|----------|----------|-------------------|
| 3 episodes | $2.49 | $0.83 | $0.69 | 72% | $0.30 amortized over 3 |
| 5 episodes | $4.99 | $1.00 | $1.15 | 74% | $0.30 amortized over 5 |
| 10 episodes | $6.99 | $0.70 | $2.30 | 67% | $0.30 amortized over 10 |
| 25 episodes | $14.99 | $0.60 | $5.75 | 62% | $0.30 amortized over 25 |

**Recommended: 5-pack at $4.99.** Clean $1.00/episode price point with 74% margin. Two packs/month ($9.98) costs more than the $9 subscription, creating an obvious upsell moment. The 10-pack at $6.99 is dangerously close to the $9 subscription value — requires careful positioning.

### Option C: Character-Based Metering

Charge by the character, directly reflecting our primary cost driver (Google Cloud TTS).

| Price per 1K chars | Our TTS COGS | Markup | Margin % |
|--------------------|--------------|--------|----------|
| $0.02 | $0.004 | 5x | 80% |
| $0.03 | $0.004 | 7.5x | 87% |
| $0.04 | $0.004 | 10x | 90% |

A typical 15K-char episode would cost the user $0.30–$0.60. A 50K-char episode: $1.00–$2.00.

**Tradeoff:** Most accurate reflection of costs but confusing for users. People don't think in characters — they think in articles. Creates anxiety about "how much will this cost me?" before every conversion.

---

## Implementation Paths

### Path 1: Stripe Checkout Per-Episode (Simplest)

**How it works:** Each time a PAYG user creates an episode, redirect to Stripe Checkout for a one-time payment. Episode is created after payment succeeds.

**Pros:**
- Minimal code changes — reuse existing `CreatesCheckoutSession` pattern
- No balance/credit system to build or maintain
- No refund complexity — pay before generation
- Stripe handles all payment UI and compliance

**Cons:**
- Terrible UX — Stripe redirect for every single episode
- High per-transaction Stripe fees ($0.30 + 2.9% per episode kills margin on cheap items)
- At $0.99/episode, Stripe takes ~$0.33, leaving $0.66 revenue → $0.43 actual margin (43%)
- Latency — user waits for payment flow before episode starts generating

**Implementation effort:** Small. Add a one-time price in Stripe, new checkout mode, webhook handler for one-time payments.

**Key files changed:**
- `app/services/creates_checkout_session.rb` — add one-time payment mode
- `app/controllers/checkout_controller.rb` — handle one-time payment success
- `app/controllers/episodes_controller.rb` — gate creation on payment for PAYG users
- `app/views/pages/home.html.erb` — add PAYG pricing to landing page

### Path 2: Pre-Paid Credit Balance (Recommended)

**How it works:** Users purchase credits via Stripe Checkout. Credits are stored in our database. Each episode creation deducts one credit. When credits run out, prompt to buy more or subscribe.

**Pros:**
- Good UX — no payment friction at episode creation time
- Amortized Stripe fees across multiple episodes
- Creates psychological commitment (sunk cost of purchased credits)
- Simple mental model: 1 credit = 1 episode
- Natural upsell moment when credits run low

**Cons:**
- Must build credit balance system (new model, ledger logic)
- Must handle edge cases: refunds, expired credits, negative balances
- Regulatory consideration: stored-value / prepaid balance laws vary by jurisdiction (though small amounts generally exempt)
- Need to decide credit expiration policy

**Implementation effort:** Medium. New `CreditBalance` model, purchase flow, deduction logic, balance display in UI.

**Key files changed:**
- New: `app/models/credit_balance.rb` — tracks user credit balance
- New: `app/models/credit_purchase.rb` — records purchase history
- New: `app/services/purchases_credits.rb` — Stripe one-time checkout → credit grant
- New: `app/services/deducts_credit.rb` — atomic credit deduction on episode create
- Modified: `app/services/checks_episode_creation_permission.rb` — allow creation if credits > 0
- Modified: `app/controllers/checkout_controller.rb` — handle credit purchase webhook
- Modified: `app/controllers/episodes_controller.rb` — check credits for PAYG users
- Modified: `app/views/billing/show.html.erb` — show credit balance
- Modified: `app/views/pages/home.html.erb` — add PAYG pricing option

### Path 3: Stripe Usage-Based Billing (Most Complex)

**How it works:** Use Stripe's metered billing API. User has an active metered subscription. Each episode reports usage to Stripe. Stripe invoices at end of billing period.

**Pros:**
- Stripe handles all metering, invoicing, and payment
- Post-pay model means zero friction at creation time
- Scales naturally with usage
- Professional invoicing for business users

**Cons:**
- Significant complexity — Stripe metered subscriptions are notoriously tricky
- Post-pay creates bad debt risk (user generates episodes, then payment fails)
- Requires minimum commitment or payment method on file
- Stripe metered billing has been deprecated in favor of their newer "Usage-based billing" which adds further migration risk
- Harder to reason about for casual users ("what will my bill be?")
- Webhook complexity increases substantially

**Implementation effort:** Large. Stripe metered subscription setup, usage reporting API integration, invoice handling, failed payment recovery.

**Key files changed:**
- Modified: `app/services/creates_checkout_session.rb` — metered subscription mode
- New: `app/services/reports_usage_to_stripe.rb` — meter event reporting
- Modified: `app/services/routes_stripe_webhook.rb` — handle invoice events
- Modified: `app/models/subscription.rb` — metered subscription type
- New: `app/services/handles_failed_invoice.rb` — bad debt recovery
- Modified: multiple views for usage display and billing history

---

## Comparison Matrix

| Criterion | Path 1: Per-Episode Checkout | Path 2: Credit Balance | Path 3: Stripe Metered |
|-----------|------------------------------|------------------------|------------------------|
| User experience | Poor | Good | Good |
| Implementation effort | Small | Medium | Large |
| Stripe fee impact | Severe (~33% of $0.99) | Amortized | Amortized |
| Effective margin at $0.99 | ~43% | ~77% | ~77% |
| Bad debt risk | None | None | Yes |
| Maintenance burden | Low | Medium | High |
| Upsell to subscription | Weak | Strong | Moderate |
| Regulatory complexity | None | Low | None |

---

## Strategic Analysis: Should We Do This At All?

### Arguments FOR Adding PAYG

1. **Captures the "casual user" segment.** Free tier users who hit the 2-episode limit but won't commit to $9/month. PAYG is the middle ground.
2. **Lower barrier to first payment.** $0.99 is easier to say yes to than $9/month. Once a user pays anything, conversion to subscription becomes more likely.
3. **Revenue from long-tail users.** Many apps find that a large number of low-usage users collectively generate significant revenue when given a micro-payment option.
4. **Competitive positioning.** Most TTS/podcast tools charge per-use. Offering both models covers more market preferences.

### Arguments AGAINST Adding PAYG

1. **Cannibalization risk.** Some $9/month subscribers who only use 5–8 episodes/month might downgrade to PAYG, reducing revenue per user.
2. **Complexity cost.** Every new billing model adds code, support burden, edge cases, and cognitive load for users on the pricing page.
3. **Small user base reality.** If the current user base is small, the incremental revenue from PAYG may not justify the engineering and support investment.
4. **Subscription is simpler to grow.** Recurring revenue is more predictable and valuable (higher LTV, better for forecasting). PAYG revenue is volatile.
5. **Margin pressure.** At low price points ($0.99), Stripe's fixed $0.30 fee is painful. Credit packs mitigate this but add complexity.

---

## Recommendation

### Add PAYG via Credit Packs (Path 2, Option B) — but keep subscriptions as the primary model.

**Specifically:**

1. **Keep the existing Free / Premium subscription tiers unchanged.** Subscriptions remain the default, most-promoted option.

2. **Add a single credit pack to start:** 5 episodes for $4.99 ($1.00/episode, 74% margin after Stripe fees). This:
   - Clean $1.00/episode price — easy for users to reason about
   - Two packs/month ($9.98) exceeds the $9 subscription, creating an obvious upsell moment
   - Amortizes Stripe's $0.30 fixed fee across 5 episodes ($0.09/episode vs $0.30 for single purchases)
   - Low enough to capture casual users who balk at $9/month
   - Creates a natural upsell: "You're spending $10/month on packs — upgrade to Premium for $9 and get unlimited episodes"

3. **Credits do not expire.** Keeps things simple and avoids regulatory/trust issues. Revisit if abuse emerges.

4. **Do NOT remove subscriptions.** Recurring revenue is the backbone of a sustainable SaaS. PAYG is a funnel into subscriptions, not a replacement.

5. **Do NOT implement character-based metering.** It's confusing for users and the marginal cost accuracy doesn't justify the UX penalty.

6. **Start with one pack, measure, then iterate.** Avoid building a full credit-pack storefront on day one. Ship the minimum, watch conversion data, and expand if warranted.

### What Success Looks Like

- **Primary metric:** % of free users who purchase credits within 30 days of hitting the episode limit
- **Secondary metric:** % of credit purchasers who convert to subscription within 90 days
- **Guard rail:** Monitor whether existing subscribers downgrade. If >5% of subscribers cancel and switch to PAYG within 60 days of launch, reconsider pricing or restrict PAYG features (e.g., standard voices only)

### Estimated Revenue Impact

Assuming 100 free-tier users hitting their limit per month:
- If 10% buy a 5-pack: 10 × $4.99 = **$49.90/month** in new revenue
- If 20% of those convert to subscription within 90 days: 2 × $9 = **$18/month** incremental recurring revenue
- Net new revenue: modest but with compounding subscription conversions

The real value is not the direct PAYG revenue — it's the reduction in friction from free → paying customer → subscriber.

---

## Implementation Plan

### Phase 1: Database & Models

#### Migration 1: Create `credit_balances` table

```ruby
# db/migrate/XXXXXX_create_credit_balances.rb
class CreateCreditBalances < ActiveRecord::Migration[8.1]
  def change
    create_table :credit_balances do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.integer :balance, null: false, default: 0
      t.timestamps
    end
  end
end
```

One row per user. `balance` is the number of episode credits remaining. Unique index on `user_id` ensures one balance record per user.

#### Migration 2: Create `credit_transactions` table

```ruby
# db/migrate/XXXXXX_create_credit_transactions.rb
class CreateCreditTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :credit_transactions do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.integer :amount, null: false           # +5 for purchase, -1 for usage
      t.integer :balance_after, null: false     # snapshot of balance after this txn
      t.string :transaction_type, null: false   # "purchase" or "usage"
      t.string :stripe_session_id              # only for purchases
      t.references :episode, foreign_key: true  # only for usage
      t.timestamps
    end

    add_index :credit_transactions, :transaction_type
    add_index :credit_transactions, :stripe_session_id, unique: true
  end
end
```

This is the ledger. Every credit change (purchase or deduction) gets a row. The `stripe_session_id` unique index prevents double-granting on duplicate webhooks. The `episode` reference links deductions to the specific episode they were spent on.

#### New Model: `CreditBalance`

```ruby
# app/models/credit_balance.rb
class CreditBalance < ApplicationRecord
  belongs_to :user

  validates :balance, numericality: { greater_than_or_equal_to: 0 }

  def self.for(user)
    find_or_create_by(user: user)
  end

  def sufficient?
    balance > 0
  end

  def deduct!
    with_lock do
      raise InsufficientCreditsError if balance <= 0
      decrement!(:balance)
    end
  end

  def add!(amount)
    with_lock do
      increment!(:balance, amount)
    end
  end

  class InsufficientCreditsError < StandardError; end
end
```

Uses `with_lock` (row-level locking) for atomic balance changes — same pattern used by the existing `EpisodeUsage#increment!`.

#### New Model: `CreditTransaction`

```ruby
# app/models/credit_transaction.rb
class CreditTransaction < ApplicationRecord
  belongs_to :user
  belongs_to :episode, optional: true

  validates :amount, presence: true
  validates :balance_after, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :transaction_type, presence: true, inclusion: { in: %w[purchase usage] }
  validates :stripe_session_id, uniqueness: true, allow_nil: true
end
```

#### Update: `User` model

```ruby
# app/models/user.rb — add association
has_one :credit_balance, dependent: :destroy
has_many :credit_transactions, dependent: :destroy
```

Add a convenience method:

```ruby
def credits_remaining
  credit_balance&.balance || 0
end

def has_credits?
  credits_remaining > 0
end
```

---

### Phase 2: Stripe Configuration

#### Add new env var and config constant

```ruby
# app/models/app_config.rb — add to Stripe module
PRICE_ID_CREDIT_PACK = ENV.fetch("STRIPE_PRICE_ID_CREDIT_PACK", "test_price_credit_pack")
```

#### Add credit pack config constants

```ruby
# app/models/app_config.rb — add new module
module Credits
  PACK_SIZE = 5
  PACK_PRICE_DISPLAY = "$4.99"
  PER_EPISODE_DISPLAY = "$1.00"
end
```

#### Create Stripe Product (manual, not code)

In the Stripe Dashboard:
1. Create a new Product: "PodRead Credit Pack — 5 Episodes"
2. Add a one-time price of $4.99
3. Copy the price ID → set as `STRIPE_PRICE_ID_CREDIT_PACK` env var

---

### Phase 3: Backend Services

#### Update: `ValidatesPrice`

```ruby
# app/services/validates_price.rb
class ValidatesPrice
  VALID_PRICE_IDS = [
    AppConfig::Stripe::PRICE_ID_MONTHLY,
    AppConfig::Stripe::PRICE_ID_ANNUAL
  ].freeze

  CREDIT_PRICE_IDS = [
    AppConfig::Stripe::PRICE_ID_CREDIT_PACK
  ].freeze

  ALL_VALID = (VALID_PRICE_IDS + CREDIT_PRICE_IDS).freeze

  def self.call(price_id)
    if ALL_VALID.include?(price_id)
      Result.success(price_id)
    else
      Result.failure("Invalid price selected")
    end
  end

  def self.credit_purchase?(price_id)
    CREDIT_PRICE_IDS.include?(price_id)
  end
end
```

#### Update: `CreatesCheckoutSession`

The key change: credit pack purchases use `mode: "payment"` (one-time) instead of `mode: "subscription"`.

```ruby
# app/services/creates_checkout_session.rb — update create_checkout_session method

def create_checkout_session(customer_id)
  session_params = {
    customer: customer_id,
    line_items: [ { price: price_id, quantity: 1 } ],
    success_url: success_url,
    cancel_url: cancel_url,
    metadata: { user_id: user.id }
  }

  if ValidatesPrice.credit_purchase?(price_id)
    session_params[:mode] = "payment"
  else
    session_params[:mode] = "subscription"
  end

  Stripe::Checkout::Session.create(session_params)
end
```

#### New Service: `GrantsCredits`

```ruby
# app/services/grants_credits.rb
class GrantsCredits
  def self.call(user:, amount:, stripe_session_id:)
    new(user:, amount:, stripe_session_id:).call
  end

  def initialize(user:, amount:, stripe_session_id:)
    @user = user
    @amount = amount
    @stripe_session_id = stripe_session_id
  end

  def call
    ActiveRecord::Base.transaction do
      balance = CreditBalance.for(user)
      balance.add!(amount)

      CreditTransaction.create!(
        user: user,
        amount: amount,
        balance_after: balance.balance,
        transaction_type: "purchase",
        stripe_session_id: stripe_session_id
      )

      Result.success(balance)
    end
  rescue ActiveRecord::RecordNotUnique
    # Duplicate webhook — credits already granted for this session
    Result.success(CreditBalance.for(user))
  rescue => e
    Result.failure("Failed to grant credits: #{e.message}")
  end

  private

  attr_reader :user, :amount, :stripe_session_id
end
```

The `RecordNotUnique` rescue handles duplicate Stripe webhooks safely — the unique index on `stripe_session_id` prevents double-granting.

#### New Service: `DeductsCredit`

```ruby
# app/services/deducts_credit.rb
class DeductsCredit
  def self.call(user:, episode:)
    new(user:, episode:).call
  end

  def initialize(user:, episode:)
    @user = user
    @episode = episode
  end

  def call
    ActiveRecord::Base.transaction do
      balance = CreditBalance.for(user)
      balance.deduct!

      CreditTransaction.create!(
        user: user,
        amount: -1,
        balance_after: balance.balance,
        transaction_type: "usage",
        episode: episode
      )

      Result.success(balance)
    end
  rescue CreditBalance::InsufficientCreditsError
    Result.failure("No credits remaining")
  rescue => e
    Result.failure("Failed to deduct credit: #{e.message}")
  end

  private

  attr_reader :user, :episode
end
```

#### Update: `RoutesStripeWebhook`

Add handling for one-time payment completions alongside the existing subscription flow.

```ruby
# app/services/routes_stripe_webhook.rb — update the checkout.session.completed case
when "checkout.session.completed"
  session = event.data.object

  if session.mode == "payment"
    # Credit pack purchase
    GrantsCreditFromCheckout.call(session: session)
  else
    # Subscription purchase (existing flow)
    result = CreatesSubscriptionFromCheckout.call(session: session)
    if result.success?
      subscription = result.data
      SendsWelcomeEmail.call(user: subscription.user, subscription: subscription)
    end
    result
  end
```

#### New Service: `GrantsCreditFromCheckout`

```ruby
# app/services/grants_credit_from_checkout.rb
class GrantsCreditFromCheckout
  def self.call(session:)
    new(session:).call
  end

  def initialize(session:)
    @session = session
  end

  def call
    user = User.find_by!(stripe_customer_id: session.customer)

    GrantsCredits.call(
      user: user,
      amount: AppConfig::Credits::PACK_SIZE,
      stripe_session_id: session.id
    )
  end

  private

  attr_reader :session
end
```

#### Update: `ChecksEpisodeCreationPermission`

Free users with credits should be allowed to create episodes beyond the 2/month free limit.

```ruby
# app/services/checks_episode_creation_permission.rb
def call
  return Result.success if skip_tracking?
  return Result.success(nil, source: :credits) if user.has_credits?

  usage = EpisodeUsage.current_for(user)
  remaining = AppConfig::Tiers::FREE_MONTHLY_EPISODES - usage.episode_count

  if remaining > 0
    Result.success(nil, remaining: remaining)
  else
    Result.failure("Episode limit reached")
  end
end
```

#### Update: `EpisodesController#handle_create_result`

After a successful episode creation, deduct a credit if the user is free and used credits (not a free-tier episode).

```ruby
# app/controllers/episodes_controller.rb — update handle_create_result
def handle_create_result(result, success_notice)
  if result.success?
    episode = result.data
    deduct_credit_if_needed(episode)
    RecordsEpisodeUsage.call(user: Current.user)
    redirect_to episodes_path, notice: success_notice
  else
    flash.now[:alert] = result.error
    @episode = @podcast.episodes.build
    render :new, status: :unprocessable_entity
  end
end

def deduct_credit_if_needed(episode)
  return unless Current.user.free?

  usage = EpisodeUsage.current_for(Current.user)
  free_remaining = AppConfig::Tiers::FREE_MONTHLY_EPISODES - usage.episode_count
  return if free_remaining > 0  # Still within free tier, no credit needed

  DeductsCredit.call(user: Current.user, episode: episode)
end
```

#### Update: `EpisodesController#require_can_create_episode`

Update the error message to mention credits as an option alongside subscription upgrade.

```ruby
# app/controllers/episodes_controller.rb — update require_can_create_episode
def require_can_create_episode
  result = ChecksEpisodeCreationPermission.call(user: Current.user)
  return if result.success?

  flash[:alert] = "You've used your 2 free episodes this month. " \
                  "Buy an episode pack or upgrade to Premium for unlimited episodes."
  redirect_to upgrade_path
end
```

---

### Phase 4: Frontend — Upgrade Page (Primary Purchase Flow)

The upgrade page (`app/views/upgrades/show.html.erb`) is what free users see. This is where we add the credit pack option.

#### Update: `UpgradesController`

```ruby
# app/controllers/upgrades_controller.rb — add credit balance to the show action
def show
  @usage = EpisodeUsage.current_for(Current.user)
  @credit_balance = Current.user.credits_remaining
end
```

#### Update: `app/views/upgrades/show.html.erb`

Add a credit pack purchase section between the current plan display and the subscription upgrade section:

```erb
<%# After the Current Plan section, before the Upgrade to Premium section %>

<%# Credit Pack section %>
<div class="grid grid-cols-1 gap-x-8 gap-y-10 border-b border-mist-950/10 pb-12 md:grid-cols-3 dark:border-white/10">
  <div>
    <h2 class="text-base/7 font-semibold text-mist-950 dark:text-white">Episode Pack</h2>
    <p class="mt-1 text-sm/6 text-mist-500 dark:text-mist-400">Buy episodes without a subscription.</p>
  </div>
  <div class="md:col-span-2">
    <div class="rounded-xl bg-white p-6 shadow-sm ring-1 ring-mist-950/5 dark:bg-mist-800 dark:ring-white/10">
      <% if @credit_balance > 0 %>
        <p class="text-sm/6 text-mist-500 dark:text-mist-400 mb-4">
          You have <span class="font-semibold text-mist-950 dark:text-white"><%= @credit_balance %> episode<%= @credit_balance == 1 ? "" : "s" %></span> remaining.
        </p>
      <% end %>

      <div class="flex items-baseline gap-2">
        <span class="text-2xl font-semibold tracking-tight text-mist-950 dark:text-white">
          <%= AppConfig::Credits::PACK_PRICE_DISPLAY %>
        </span>
        <span class="text-sm text-mist-500 dark:text-mist-400">
          for <%= AppConfig::Credits::PACK_SIZE %> episodes (<%= AppConfig::Credits::PER_EPISODE_DISPLAY %>/episode)
        </span>
      </div>

      <ul class="mt-4 space-y-2 text-sm text-mist-500 dark:text-mist-400">
        <li class="flex items-center gap-2">
          <svg class="size-4 text-green-500" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd" />
          </svg>
          Credits never expire
        </li>
        <li class="flex items-center gap-2">
          <svg class="size-4 text-green-500" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd" />
          </svg>
          Up to 50,000 characters per episode
        </li>
        <li class="flex items-center gap-2">
          <svg class="size-4 text-green-500" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd" />
          </svg>
          No subscription required
        </li>
      </ul>

      <%= form_with url: checkout_path, method: :post, class: "mt-6", data: { turbo: false } do |form| %>
        <%= form.hidden_field :price_id, value: AppConfig::Stripe::PRICE_ID_CREDIT_PACK %>
        <%= form.submit "Buy #{AppConfig::Credits::PACK_SIZE} Episodes — #{AppConfig::Credits::PACK_PRICE_DISPLAY}",
          class: "w-full rounded-lg bg-mist-950 dark:bg-white px-4 py-2.5 text-center text-sm font-semibold text-white dark:text-mist-950 shadow-sm hover:bg-mist-800 dark:hover:bg-mist-200 cursor-pointer" %>
      <% end %>
    </div>
  </div>
</div>
```

#### Update: Character limit for credit users

Credit-pack users should get the premium character limit (50K) when spending credits.

```ruby
# app/models/user.rb — update character_limit
def character_limit
  return nil if unlimited?
  return AppConfig::Tiers::PREMIUM_CHARACTER_LIMIT if premium?
  return AppConfig::Tiers::PREMIUM_CHARACTER_LIMIT if has_credits?
  AppConfig::Tiers::FREE_CHARACTER_LIMIT
end
```

---

### Phase 5: Frontend — Billing Page

Users who have purchased credits but also have a subscription should see their credit balance on the billing page.

#### Update: `BillingController`

```ruby
# app/controllers/billing_controller.rb
def show
  redirect_to upgrade_path and return if Current.user.free? && !Current.user.has_credits?
  @subscription = Current.user.subscription
  @credit_balance = Current.user.credits_remaining
  @credit_transactions = Current.user.credit_transactions.order(created_at: :desc).limit(10)
end
```

Note the updated redirect logic: free users with credits should see the billing page, not be bounced to upgrade.

#### Update: `app/views/billing/show.html.erb`

Add a credit balance section after the Current Plan section:

```erb
<%# After the Current Plan section %>

<% if @credit_balance > 0 || @credit_transactions.any? %>
  <div class="grid grid-cols-1 gap-x-8 gap-y-10 border-b border-mist-950/10 pb-12 md:grid-cols-3 dark:border-white/10">
    <div>
      <h2 class="text-base/7 font-semibold text-mist-950 dark:text-white">Episode Credits</h2>
      <p class="mt-1 text-sm/6 text-mist-500 dark:text-mist-400">Your prepaid episode balance.</p>
    </div>
    <div class="md:col-span-2">
      <div class="rounded-xl bg-white p-6 shadow-sm ring-1 ring-mist-950/5 dark:bg-mist-800 dark:ring-white/10">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-3xl font-semibold text-mist-950 dark:text-white"><%= @credit_balance %></p>
            <p class="text-sm text-mist-500 dark:text-mist-400">episodes remaining</p>
          </div>
          <%= form_with url: checkout_path, method: :post, data: { turbo: false } do |form| %>
            <%= form.hidden_field :price_id, value: AppConfig::Stripe::PRICE_ID_CREDIT_PACK %>
            <%= form.submit "Buy More",
              class: "rounded-lg bg-mist-950 dark:bg-white px-4 py-2 text-sm font-semibold text-white dark:text-mist-950 shadow-sm hover:bg-mist-800 dark:hover:bg-mist-200 cursor-pointer" %>
          <% end %>
        </div>
      </div>
    </div>
  </div>
<% end %>
```

---

### Phase 6: Frontend — Episode Creation Awareness

Show users their remaining credits when creating an episode so they know what they're spending.

#### Update: `EpisodesController#new`

```ruby
# app/controllers/episodes_controller.rb — update new action
def new
  @episode = @podcast.episodes.build
  @credit_info = credit_info_for_current_user
end

# Add private method
def credit_info_for_current_user
  return nil unless Current.user.free?

  usage = EpisodeUsage.current_for(Current.user)
  free_remaining = AppConfig::Tiers::FREE_MONTHLY_EPISODES - usage.episode_count

  if free_remaining > 0
    { source: :free, remaining: free_remaining }
  elsif Current.user.has_credits?
    { source: :credits, remaining: Current.user.credits_remaining }
  end
end
```

#### Update: `app/views/episodes/new.html.erb`

Add a small info banner above the tab bar:

```erb
<%# Inside the card, before the tab-switch div %>
<% if @credit_info %>
  <% if @credit_info[:source] == :free %>
    <div class="mb-4 rounded-lg bg-mist-100 dark:bg-mist-700/50 px-4 py-3 text-sm text-mist-600 dark:text-mist-300">
      <%= @credit_info[:remaining] %> of <%= AppConfig::Tiers::FREE_MONTHLY_EPISODES %> free episodes remaining this month
    </div>
  <% elsif @credit_info[:source] == :credits %>
    <div class="mb-4 rounded-lg bg-blue-50 dark:bg-blue-900/20 px-4 py-3 text-sm text-blue-700 dark:text-blue-300">
      This episode will use 1 credit. You have <strong><%= @credit_info[:remaining] %></strong> credit<%= @credit_info[:remaining] == 1 ? "" : "s" %> remaining.
    </div>
  <% end %>
<% end %>
```

---

### Phase 7: Frontend — Landing Page Pricing

Add a third pricing card — "Episode Pack" — between Free and Premium in both the Monthly and Yearly panels.

#### Update: `app/views/pages/home.html.erb`

Insert a new `pricing_hero_multi_plan` card between the Free and Premium cards in each panel:

```erb
<%= render "shared/marketing/pricing_hero_multi_plan",
  name: "Episode Pack",
  price: "$4.99",
  subheadline: "Pay as you go, no subscription needed.",
  features: [
    "5 episodes per pack",
    "Credits never expire",
    "Up to 50,000 characters",
    "Buy more anytime",
  ],
  cta_html: '<button type="button" data-action="click->signup-modal#open" data-plan="free"
    data-heading="Get started with Episode Packs"
    data-subtext="Create a free account, then buy an episode pack."
    class="inline-flex shrink-0 items-center justify-center gap-1 rounded-full text-sm/7 font-medium px-5 py-2.5 bg-mist-950/5 text-mist-950 hover:bg-mist-950/10 dark:bg-white/10 dark:text-white dark:hover:bg-white/15">Get started</button>'.html_safe %>
```

The card uses the same `pricing_hero_multi_plan` partial as Free and Premium. The grid auto-flows to 3 columns on desktop via `lg:auto-cols-fr lg:grid-flow-col`. The CTA opens the signup modal since users need an account before purchasing credits. The Episode Pack card is identical in both Monthly and Yearly panels since it's a one-time purchase unaffected by billing frequency.

Also update FAQ #1 to mention episode packs: "Need more? Buy a 5-episode pack for $4.99 with no subscription, or upgrade to Premium for $9/month for unlimited episodes."

---

### Phase 8: Frontend — Header Navigation

Free users with credits should see "Billing" instead of "Upgrade" in the nav, since they're now paying customers.

#### Update: `app/views/shared/_header.html.erb`

Change the conditional from:

```erb
<% if Current.user.free? %>
  <%= link_to "Upgrade", upgrade_path, ... %>
<% else %>
  <%= link_to "Billing", billing_path, ... %>
<% end %>
```

To:

```erb
<% if Current.user.free? && !Current.user.has_credits? %>
  <%= link_to "Upgrade", upgrade_path, ... %>
<% else %>
  <%= link_to "Billing", billing_path, ... %>
<% end %>
```

Apply this change in both the desktop nav and the mobile menu dialog (two locations in `_header.html.erb`).

---

### Phase 9: Checkout Success Page

After purchasing credits, the user should see a confirmation that credits were added.

#### Update: `CheckoutController#success`

```ruby
# app/controllers/checkout_controller.rb
def success
  @credit_balance = Current.user.credits_remaining if Current.user.has_credits?
end
```

#### Update: `app/views/checkout/success.html.erb`

Add a conditional message for credit purchases:

```erb
<% if @credit_balance %>
  <p class="text-sm text-mist-500 dark:text-mist-400 mt-2">
    Your credits have been added. You now have <strong><%= @credit_balance %></strong> episode credits.
  </p>
<% end %>
```

---

### Phase 10: Upsell Nudge

When a credit user's balance drops to 1 or 0, nudge them toward a subscription.

#### Update: `DeductsCredit` (add nudge logic)

After deducting, check if the user should be nudged:

```ruby
# In DeductsCredit#call, after creating the CreditTransaction:
if balance.balance == 0
  SendsCreditDepletedNudge.call(user: user)
end
```

#### New Service: `SendsCreditDepletedNudge`

```ruby
# app/services/sends_credit_depleted_nudge.rb
class SendsCreditDepletedNudge
  def self.call(user:)
    return unless user.free?
    return if user.sent_messages.exists?(message_type: "credit_depleted")

    BillingMailer.credit_depleted(user).deliver_later
    user.sent_messages.create!(message_type: "credit_depleted")
  end
end
```

#### New Mailer Template: `BillingMailer#credit_depleted`

```ruby
# app/mailers/billing_mailer.rb — add method
def credit_depleted(user)
  @user = user
  mail(to: user.email_address, subject: "Your PodRead credits are used up")
end
```

Email body should highlight: "You've used all your episode credits. Buy another pack for $4.99, or upgrade to Premium for $9/month for unlimited episodes."

---

### Phase 11: Tests

#### Model Tests

| Test file | What to test |
|-----------|-------------|
| `test/models/credit_balance_test.rb` | `for` creates or finds, `deduct!` decrements, `deduct!` raises at zero, `add!` increments, thread safety with lock |
| `test/models/credit_transaction_test.rb` | Validations, uniqueness of `stripe_session_id`, associations |

#### Service Tests

| Test file | What to test |
|-----------|-------------|
| `test/services/grants_credits_test.rb` | Adds balance, creates transaction record, idempotent on duplicate `stripe_session_id` |
| `test/services/deducts_credit_test.rb` | Deducts 1, creates usage transaction, fails when balance is 0, links to episode |
| `test/services/grants_credit_from_checkout_test.rb` | Finds user by `stripe_customer_id`, grants correct pack size |
| `test/services/validates_price_test.rb` | Accepts credit pack price ID, `credit_purchase?` returns true/false correctly |
| `test/services/checks_episode_creation_permission_test.rb` | Free user with credits is allowed, free user with no credits and no free episodes is denied |

#### Controller / Integration Tests

| Test file | What to test |
|-----------|-------------|
| `test/controllers/checkout_controller_test.rb` | Credit pack price ID creates a payment-mode checkout session |
| `test/controllers/episodes_controller_test.rb` | Free user with credits can create episode, credit is deducted, credit info displays on new page |
| `test/controllers/billing_controller_test.rb` | Free user with credits sees billing page (not redirected to upgrade) |
| `test/services/routes_stripe_webhook_test.rb` | `checkout.session.completed` with `mode: "payment"` calls `GrantsCreditFromCheckout` |

---

### File Change Summary

| Action | File | Change |
|--------|------|--------|
| **NEW** | `db/migrate/..._create_credit_balances.rb` | Migration |
| **NEW** | `db/migrate/..._create_credit_transactions.rb` | Migration |
| **NEW** | `app/models/credit_balance.rb` | Model |
| **NEW** | `app/models/credit_transaction.rb` | Model |
| **NEW** | `app/services/grants_credits.rb` | Service |
| **NEW** | `app/services/deducts_credit.rb` | Service |
| **NEW** | `app/services/grants_credit_from_checkout.rb` | Service |
| **NEW** | `app/services/sends_credit_depleted_nudge.rb` | Service |
| **NEW** | `app/views/billing_mailer/credit_depleted.html.erb` | Email template |
| **NEW** | Tests (8–10 new test files) | Test coverage |
| MODIFY | `app/models/user.rb` | Add associations + `has_credits?` + `credits_remaining` + update `character_limit` |
| MODIFY | `app/models/app_config.rb` | Add `Credits` module + `PRICE_ID_CREDIT_PACK` |
| MODIFY | `app/services/validates_price.rb` | Accept credit pack price ID |
| MODIFY | `app/services/creates_checkout_session.rb` | Payment mode for credit packs |
| MODIFY | `app/services/routes_stripe_webhook.rb` | Route one-time payment webhooks |
| MODIFY | `app/services/checks_episode_creation_permission.rb` | Allow creation with credits |
| MODIFY | `app/controllers/episodes_controller.rb` | Deduct credit, show credit info |
| MODIFY | `app/controllers/billing_controller.rb` | Show credits, update redirect logic |
| MODIFY | `app/controllers/checkout_controller.rb` | Credit balance on success page |
| MODIFY | `app/views/upgrades/show.html.erb` | Add credit pack purchase card |
| MODIFY | `app/views/billing/show.html.erb` | Add credit balance display |
| MODIFY | `app/views/episodes/new.html.erb` | Show credit usage info banner |
| MODIFY | `app/views/checkout/success.html.erb` | Credit confirmation message |
| MODIFY | `app/views/shared/_header.html.erb` | Nav link logic for credit users |
| MODIFY | `app/views/pages/home.html.erb` | Subtle PAYG mention on pricing |
| MODIFY | `app/mailers/billing_mailer.rb` | Add `credit_depleted` method |

Total: ~10 new files, ~16 modified files.

---

### Implementation Order

Ship in this order to keep PRs reviewable:

1. **PR 1 — Database + Models**: Migrations, `CreditBalance`, `CreditTransaction`, `User` associations. No user-facing changes.
2. **PR 2 — Purchase Flow**: `ValidatesPrice`, `CreatesCheckoutSession`, `GrantsCredits`, `GrantsCreditFromCheckout`, webhook routing. Enables buying credits but not spending them yet.
3. **PR 3 — Spending Credits**: `ChecksEpisodeCreationPermission`, `DeductsCredit`, `EpisodesController` changes, character limit update. Credits become functional.
4. **PR 4 — Frontend**: Upgrade page credit card, billing page balance, episode creation info banner, header nav, pricing page mention, checkout success.
5. **PR 5 — Nudge**: `SendsCreditDepletedNudge`, mailer template. Low risk, independent.
