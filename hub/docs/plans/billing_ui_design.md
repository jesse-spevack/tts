# Billing Management UI Design

## Overview

User-facing pages for viewing pricing, upgrading to PRO, and managing subscriptions.

## Pages

### 1. Pricing Page (`/pricing`)

Public page showing plan comparison.

```
┌─────────────────────────────────────────────────────────────┐
│                    Simple Pricing                           │
│          Turn your reading list into a podcast              │
├────────────────────────┬────────────────────────────────────┤
│         FREE           │              PRO                   │
│          $0            │           $9/month                 │
│                        │         $89/year (save 17%)        │
├────────────────────────┼────────────────────────────────────┤
│ ✓ 2 episodes/month     │ ✓ Unlimited episodes               │
│ ✓ Up to 15K chars      │ ✓ Up to 50K chars (~65 min)        │
│ ✓ Standard voice       │ ✓ Standard voice                   │
│ ✓ RSS feed             │ ✓ RSS feed                         │
├────────────────────────┼────────────────────────────────────┤
│   [Get Started Free]   │      [Upgrade to PRO]              │
└────────────────────────┴────────────────────────────────────┘

FAQ:
- What counts as a character?
- Can I cancel anytime?
- What happens to my episodes if I downgrade?
```

### 2. Billing Page (`/billing`)

Authenticated page for managing subscription.

**For FREE users:**
```
┌─────────────────────────────────────────────────────────────┐
│  Your Plan: FREE                                            │
│                                                             │
│  Episodes this month: 1 of 2 used                           │
│  Character limit: 15,000 per episode                        │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Upgrade to PRO for unlimited episodes                │  │
│  │  $9/month or $89/year (save 17%)                      │  │
│  │                                                       │  │
│  │  [Upgrade Monthly]  [Upgrade Annual]                  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**For PRO users:**
```
┌─────────────────────────────────────────────────────────────┐
│  Your Plan: PRO ($9/month)                                  │
│                                                             │
│  Next billing date: December 15, 2025                       │
│  Character limit: 50,000 per episode                        │
│                                                             │
│  [Manage Payment Method]  [Cancel Subscription]             │
└─────────────────────────────────────────────────────────────┘
```

**For UNLIMITED users:**
```
┌─────────────────────────────────────────────────────────────┐
│  Your Plan: UNLIMITED                                       │
│                                                             │
│  No limits. Premium voice enabled.                          │
└─────────────────────────────────────────────────────────────┘
```

### 3. Checkout Success (`/subscriptions/success`)

```
┌─────────────────────────────────────────────────────────────┐
│                     Welcome to PRO!                         │
│                                                             │
│  Your subscription is now active.                           │
│                                                             │
│  ✓ Unlimited episodes                                       │
│  ✓ Up to 50,000 characters per episode                      │
│                                                             │
│              [Create Your First Episode]                    │
└─────────────────────────────────────────────────────────────┘
```

## Routes

```ruby
# config/routes.rb
get "/pricing", to: "pages#pricing"
get "/billing", to: "billing#show"

resources :subscriptions, only: [] do
  collection do
    post :checkout
    get :success
    get :cancel
  end
end
```

## Controllers

### BillingController

```ruby
class BillingController < ApplicationController
  before_action :require_authentication

  def show
    @usage = EpisodeUsage.current_for(Current.user)
    @subscription = Current.user.subscription
  end
end
```

## Views

| View | Purpose |
|------|---------|
| `pages/pricing.html.erb` | Public pricing comparison |
| `billing/show.html.erb` | Subscription management |
| `subscriptions/success.html.erb` | Post-checkout confirmation |
| `subscriptions/cancel.html.erb` | Checkout canceled |

## Navigation Updates

Add to header/nav:
- "Pricing" link (public)
- "Billing" link (authenticated users)

Show current plan badge in episodes index:
- "FREE: 1 of 2 episodes" or "PRO" or "UNLIMITED"

## Components

### Plan Card

Reusable component for pricing page and billing page upgrade CTA.

```erb
<%= render "shared/plan_card",
    name: "PRO",
    price: "$9/month",
    features: ["Unlimited episodes", "50K chars/episode"],
    cta_text: "Upgrade",
    cta_path: subscriptions_checkout_path(price: "monthly") %>
```

### Usage Display

Show remaining episodes for free users.

```erb
<% if Current.user.free? %>
  <div class="usage-display">
    <%= @usage.episode_count %> of 2 free episodes used this month
  </div>
<% end %>
```

## Files to Create

| File | Purpose |
|------|---------|
| `app/views/pages/pricing.html.erb` | Pricing page |
| `app/views/billing/show.html.erb` | Billing management |
| `app/views/subscriptions/success.html.erb` | Checkout success |
| `app/views/subscriptions/cancel.html.erb` | Checkout canceled |
| `app/views/shared/_plan_card.html.erb` | Plan comparison card |
| `app/controllers/billing_controller.rb` | Billing page |

## Dependencies

- Stripe integration must be complete
- Episode usage tracking must be complete (for showing remaining episodes)
