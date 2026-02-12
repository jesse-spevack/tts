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

## Next Steps (If Approved)

1. Create `CreditBalance` and `CreditPurchase` models with migrations
2. Build credit purchase flow via Stripe one-time Checkout
3. Modify `ChecksEpisodeCreationPermission` to allow creation when credits > 0
4. Build `DeductsCredit` service with atomic balance updates
5. Add credit balance display to billing page and episode creation UI
6. Update pricing page with PAYG option
7. Add upsell prompts when credit balance is low
8. Ship behind a feature flag, enable for new free-tier users first
