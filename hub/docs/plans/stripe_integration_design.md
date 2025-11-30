# Stripe Integration Design

## Overview

Add Stripe subscription billing to upgrade FREE users to PRO tier.

## Products & Prices

| Plan | Price | Stripe Price ID |
|------|-------|-----------------|
| PRO Monthly | $9/month | `price_pro_monthly` (create in Stripe) |
| PRO Annual | $89/year | `price_pro_annual` (create in Stripe) |

## Schema

```ruby
create_table :subscriptions do |t|
  t.references :user, null: false, foreign_key: true, index: { unique: true }
  t.string :stripe_customer_id, null: false
  t.string :stripe_subscription_id, null: false
  t.string :status, null: false, default: "active"
  t.string :price_id
  t.datetime :current_period_end
  t.timestamps

  t.index :stripe_customer_id, unique: true
  t.index :stripe_subscription_id, unique: true
end
```

### Status Values

- `active` - Subscription is current and paid
- `past_due` - Payment failed, in retry period
- `canceled` - User canceled, access ends immediately
- `unpaid` - Payment failed, no longer retrying

## Configuration

```ruby
# config/initializers/stripe.rb
Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY")

# Environment variables:
# STRIPE_SECRET_KEY - sk_test_xxx (dev) or sk_live_xxx (prod)
# STRIPE_WEBHOOK_SECRET - whsec_xxx
# STRIPE_PRICE_ID_MONTHLY - price_xxx
# STRIPE_PRICE_ID_ANNUAL - price_xxx
```

## Checkout Flow

```
User clicks "Upgrade to PRO"
       │
       ▼
POST /subscriptions/checkout
       │
       ▼
┌─────────────────────────────┐
│ CreateCheckoutSession       │
│ - Find/create Stripe cust   │
│ - Create Checkout Session   │
│ - Return session URL        │
└──────────────┬──────────────┘
               │
               ▼
    Redirect to Stripe Checkout
               │
               ▼
    User completes payment
               │
               ▼
    Stripe redirects to /subscriptions/success
               │
               ▼
    Webhook: checkout.session.completed
               │
               ▼
┌─────────────────────────────┐
│ HandleCheckoutCompleted     │
│ - Create Subscription rec   │
│ - Upgrade user to PRO       │
└─────────────────────────────┘
```

## Webhook Events

| Event | Action |
|-------|--------|
| `checkout.session.completed` | Create subscription, upgrade to PRO |
| `customer.subscription.updated` | Update status, period_end |
| `customer.subscription.deleted` | Delete subscription, downgrade to FREE |
| `invoice.payment_failed` | Update status to past_due |

## Services

### CreateCheckoutSession

```ruby
class CreateCheckoutSession
  def self.call(user:, price_id:, success_url:, cancel_url:)
    customer = find_or_create_customer(user)

    session = Stripe::Checkout::Session.create(
      customer: customer.id,
      mode: "subscription",
      line_items: [{ price: price_id, quantity: 1 }],
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: { user_id: user.id }
    )

    session.url
  end
end
```

### HandleWebhookEvent

```ruby
class HandleWebhookEvent
  def self.call(event:)
    case event.type
    when "checkout.session.completed"
      HandleCheckoutCompleted.call(session: event.data.object)
    when "customer.subscription.updated"
      HandleSubscriptionUpdated.call(subscription: event.data.object)
    when "customer.subscription.deleted"
      HandleSubscriptionDeleted.call(subscription: event.data.object)
    end
  end
end
```

### HandleSubscriptionDeleted

```ruby
class HandleSubscriptionDeleted
  def self.call(subscription:)
    sub = Subscription.find_by(stripe_subscription_id: subscription.id)
    return unless sub

    sub.user.update!(tier: :free)
    sub.destroy!
  end
end
```

## Routes

```ruby
# config/routes.rb
resources :subscriptions, only: [] do
  collection do
    post :checkout
    get :success
    get :cancel
  end
end

post "/webhooks/stripe", to: "webhooks#stripe"
```

## Files to Create

| File | Purpose |
|------|---------|
| `app/models/subscription.rb` | Subscription model |
| `app/controllers/subscriptions_controller.rb` | Checkout endpoints |
| `app/controllers/webhooks_controller.rb` | Stripe webhooks |
| `app/services/create_checkout_session.rb` | Create Stripe session |
| `app/services/handle_webhook_event.rb` | Route webhook events |
| `app/services/handle_checkout_completed.rb` | Process successful checkout |
| `app/services/handle_subscription_updated.rb` | Sync subscription changes |
| `app/services/handle_subscription_deleted.rb` | Handle cancellation |
| `config/initializers/stripe.rb` | Stripe configuration |
| `db/migrate/XXXX_create_subscriptions.rb` | Migration |

## Testing

- Use Stripe test mode in development (`sk_test_xxx`)
- Use Stripe CLI for webhook testing: `stripe listen --forward-to localhost:3000/webhooks/stripe`
- Test cards: `4242424242424242` (success), `4000000000000341` (decline)

## Dependencies

- `stripe` gem
- Tier system must be simplified first (FREE/PRO/UNLIMITED)
