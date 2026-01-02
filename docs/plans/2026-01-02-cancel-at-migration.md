# Cancel At Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace `cancel_at_period_end` boolean with `cancel_at` datetime to properly track all Stripe cancellation scenarios.

**Architecture:** Add `cancel_at` column, update `SyncsSubscription` to derive the value from both Stripe's `cancel_at` and `cancel_at_period_end` fields, update UI to use new field, then remove old boolean column.

**Tech Stack:** Rails 8.1, SQLite, Stripe API, Minitest

---

## Task 1: Add cancel_at Column

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_cancel_at_to_subscriptions.rb`
- Modify: `db/schema.rb` (auto-generated)

**Step 1: Generate migration**

Run:
```bash
bin/rails generate migration AddCancelAtToSubscriptions cancel_at:datetime
```

Expected: Creates migration file in `db/migrate/`

**Step 2: Run migration**

Run:
```bash
bin/rails db:migrate
```

Expected: Migration runs successfully, schema updated

**Step 3: Verify schema**

Run:
```bash
grep -A5 "create_table \"subscriptions\"" db/schema.rb
```

Expected: Shows `cancel_at` column in subscriptions table

**Step 4: Commit**

```bash
git add db/migrate/*_add_cancel_at_to_subscriptions.rb db/schema.rb
git commit -m "Add cancel_at column to subscriptions"
```

---

## Task 2: Update SyncsSubscription to Populate cancel_at

**Files:**
- Test: `test/services/syncs_subscription_test.rb`
- Modify: `app/services/syncs_subscription.rb`

**Step 1: Write failing test for cancel_at from Stripe cancel_at**

Add to `test/services/syncs_subscription_test.rb`:

```ruby
test "syncs cancel_at when Stripe has cancel_at timestamp" do
  @user.update!(stripe_customer_id: "cus_cancel_at")
  cancel_timestamp = 1.month.from_now.to_i

  stub_stripe_subscription(
    id: "sub_cancel_at",
    customer: "cus_cancel_at",
    status: "active",
    price_id: "price_monthly",
    current_period_end: 1.month.from_now.to_i,
    cancel_at: cancel_timestamp
  )

  result = SyncsSubscription.call(stripe_subscription_id: "sub_cancel_at")

  assert result.success?
  assert_in_delta Time.at(cancel_timestamp), result.data.cancel_at, 1.second
end
```

**Step 2: Update stub helper to support cancel_at**

Modify `stub_stripe_subscription` in `test/services/syncs_subscription_test.rb`:

```ruby
def stub_stripe_subscription(id:, customer:, status:, price_id:, current_period_end:, cancel_at_period_end: false, cancel_at: nil)
  stub_request(:get, "https://api.stripe.com/v1/subscriptions/#{id}")
    .to_return(
      status: 200,
      body: {
        id: id,
        customer: customer,
        status: status,
        cancel_at_period_end: cancel_at_period_end,
        cancel_at: cancel_at,
        items: {
          data: [ { price: { id: price_id }, current_period_end: current_period_end } ]
        }
      }.to_json
    )
end
```

**Step 3: Run test to verify it fails**

Run:
```bash
bin/rails test test/services/syncs_subscription_test.rb
```

Expected: New test FAILS (cancel_at not being synced yet)

**Step 4: Write failing test for cancel_at derived from cancel_at_period_end**

Add to `test/services/syncs_subscription_test.rb`:

```ruby
test "derives cancel_at from current_period_end when cancel_at_period_end is true" do
  @user.update!(stripe_customer_id: "cus_period_end")
  period_end = 1.month.from_now.to_i

  stub_stripe_subscription(
    id: "sub_period_end",
    customer: "cus_period_end",
    status: "active",
    price_id: "price_monthly",
    current_period_end: period_end,
    cancel_at_period_end: true
  )

  result = SyncsSubscription.call(stripe_subscription_id: "sub_period_end")

  assert result.success?
  assert_in_delta Time.at(period_end), result.data.cancel_at, 1.second
end
```

**Step 5: Write failing test for nil cancel_at when not canceling**

Add to `test/services/syncs_subscription_test.rb`:

```ruby
test "sets cancel_at to nil when subscription is not canceling" do
  @user.update!(stripe_customer_id: "cus_not_canceling")

  stub_stripe_subscription(
    id: "sub_not_canceling",
    customer: "cus_not_canceling",
    status: "active",
    price_id: "price_monthly",
    current_period_end: 1.month.from_now.to_i,
    cancel_at_period_end: false,
    cancel_at: nil
  )

  result = SyncsSubscription.call(stripe_subscription_id: "sub_not_canceling")

  assert result.success?
  assert_nil result.data.cancel_at
end
```

**Step 6: Run tests to verify they fail**

Run:
```bash
bin/rails test test/services/syncs_subscription_test.rb
```

Expected: New tests FAIL

**Step 7: Implement cancel_at syncing in SyncsSubscription**

Modify `app/services/syncs_subscription.rb`. Replace lines 19-27 with:

```ruby
      # Assumes single-item subscriptions (one price per subscription)
      item = stripe_subscription.items.data.first
      subscription.update!(
        user: user,
        status: map_status(stripe_subscription.status),
        stripe_price_id: item.price.id,
        current_period_end: Time.at(item.current_period_end),
        cancel_at_period_end: stripe_subscription.cancel_at_period_end,
        cancel_at: derive_cancel_at(stripe_subscription, item)
      )
```

Add private method after `map_status`:

```ruby
def derive_cancel_at(stripe_subscription, item)
  if stripe_subscription.cancel_at
    Time.at(stripe_subscription.cancel_at)
  elsif stripe_subscription.cancel_at_period_end
    Time.at(item.current_period_end)
  end
end
```

**Step 8: Run tests to verify they pass**

Run:
```bash
bin/rails test test/services/syncs_subscription_test.rb
```

Expected: All tests PASS

**Step 9: Run full test suite**

Run:
```bash
bin/rails test
```

Expected: All tests PASS

**Step 10: Commit**

```bash
git add app/services/syncs_subscription.rb test/services/syncs_subscription_test.rb
git commit -m "Sync cancel_at from Stripe, deriving from cancel_at or cancel_at_period_end"
```

---

## Task 3: Add canceling? Helper Method to Subscription Model

**Files:**
- Test: `test/models/subscription_test.rb`
- Modify: `app/models/subscription.rb`

**Step 1: Write failing tests for canceling? method**

Add to `test/models/subscription_test.rb`:

```ruby
test "canceling? returns true when cancel_at is present" do
  subscription = Subscription.new(cancel_at: 1.month.from_now)
  assert subscription.canceling?
end

test "canceling? returns false when cancel_at is nil" do
  subscription = Subscription.new(cancel_at: nil)
  refute subscription.canceling?
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
bin/rails test test/models/subscription_test.rb
```

Expected: Tests FAIL (method doesn't exist)

**Step 3: Implement canceling? method**

Add to `app/models/subscription.rb` after the validations:

```ruby
def canceling?
  cancel_at.present?
end
```

**Step 4: Run tests to verify they pass**

Run:
```bash
bin/rails test test/models/subscription_test.rb
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add app/models/subscription.rb test/models/subscription_test.rb
git commit -m "Add canceling? helper method to Subscription model"
```

---

## Task 4: Update Billing View to Use cancel_at

**Files:**
- Modify: `app/views/billing/show.html.erb`

**Step 1: Update billing view to use canceling? and cancel_at**

In `app/views/billing/show.html.erb`, replace lines 17-24:

```erb
<% elsif @subscription&.active? %>
  <%= render "shared/card", padding: "p-4 sm:p-8" do %>
    <h2 class="text-lg font-medium mb-2">Premium Plan</h2>
    <p class="text-[var(--color-subtext)] text-sm mb-4">
      <% if @subscription.canceling? %>
        Ends on <%= @subscription.cancel_at.strftime("%B %d, %Y") %>
      <% else %>
        Renews on <%= @subscription.current_period_end.strftime("%B %d, %Y") %>
      <% end %>
    </p>
    <%= button_to "Manage Subscription", portal_session_path, class: button_classes(type: :secondary), data: { turbo: false } %>
  <% end %>
```

**Step 2: Verify the app runs**

Run:
```bash
bin/rails test
```

Expected: All tests PASS

**Step 3: Commit**

```bash
git add app/views/billing/show.html.erb
git commit -m "Update billing view to use cancel_at instead of cancel_at_period_end"
```

---

## Task 5: Update Fixtures for Testing

**Files:**
- Modify: `test/fixtures/subscriptions.yml`

**Step 1: Update fixtures to include cancel_at**

Modify `test/fixtures/subscriptions.yml`:

```yaml
active_subscription:
  user: subscriber
  stripe_subscription_id: sub_test_active
  stripe_price_id: price_monthly
  status: 0
  current_period_end: <%= 1.month.from_now %>

canceled_subscription:
  user: canceled_subscriber
  stripe_subscription_id: sub_test_canceled
  stripe_price_id: price_monthly
  status: 2
  current_period_end: <%= 1.day.ago %>

past_due_subscription:
  user: past_due_subscriber
  stripe_subscription_id: sub_test_past_due
  stripe_price_id: price_monthly
  status: 1
  current_period_end: <%= 1.week.from_now %>

canceling_subscription:
  user: canceling_subscriber
  stripe_subscription_id: sub_test_canceling
  stripe_price_id: price_monthly
  status: 0
  current_period_end: <%= 1.month.from_now %>
  cancel_at_period_end: true
  cancel_at: <%= 1.month.from_now %>
```

**Step 2: Run tests to verify fixtures work**

Run:
```bash
bin/rails test
```

Expected: All tests PASS

**Step 3: Commit**

```bash
git add test/fixtures/subscriptions.yml
git commit -m "Update subscription fixtures to include cancel_at"
```

---

## Task 6: Update Rake Task Output

**Files:**
- Modify: `lib/tasks/subscriptions.rake`

**Step 1: Update rake task to show cancel_at instead of cancel_at_period_end**

Modify `lib/tasks/subscriptions.rake`:

```ruby
namespace :subscriptions do
  desc "Resync all subscriptions from Stripe to update cancellation status"
  task resync_all: :environment do
    total = Subscription.count
    puts "Resyncing #{total} subscriptions..."

    Subscription.find_each.with_index do |subscription, index|
      result = SyncsSubscription.call(stripe_subscription_id: subscription.stripe_subscription_id)

      if result.success?
        sub = result.data
        status = if sub.canceling?
          "canceling (#{sub.cancel_at.strftime('%Y-%m-%d')})"
        else
          sub.status
        end
        puts "[#{index + 1}/#{total}] #{subscription.stripe_subscription_id}: #{status}"
      else
        puts "[#{index + 1}/#{total}] #{subscription.stripe_subscription_id}: FAILED - #{result.error}"
      end

      sleep 0.1 # Rate limit Stripe API calls
    end

    puts "Done!"
  end
end
```

**Step 2: Commit**

```bash
git add lib/tasks/subscriptions.rake
git commit -m "Update subscriptions rake task to show cancel_at date"
```

---

## Task 7: Remove cancel_at_period_end Column

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_remove_cancel_at_period_end_from_subscriptions.rb`
- Modify: `app/models/subscription.rb`
- Modify: `app/services/syncs_subscription.rb`
- Modify: `test/services/syncs_subscription_test.rb`
- Modify: `test/fixtures/subscriptions.yml`

**Step 1: Remove cancel_at_period_end from SyncsSubscription**

In `app/services/syncs_subscription.rb`, remove the `cancel_at_period_end` line from the update! call:

```ruby
subscription.update!(
  user: user,
  status: map_status(stripe_subscription.status),
  stripe_price_id: item.price.id,
  current_period_end: Time.at(item.current_period_end),
  cancel_at: derive_cancel_at(stripe_subscription, item)
)
```

**Step 2: Remove old tests that reference cancel_at_period_end directly**

In `test/services/syncs_subscription_test.rb`, remove these two tests:
- `test "syncs cancel_at_period_end when true"`
- `test "syncs cancel_at_period_end when false"`

**Step 3: Update stub helper to not need cancel_at_period_end in assertions**

The stub helper still needs `cancel_at_period_end` because Stripe returns it, but our tests no longer assert on the model's `cancel_at_period_end` attribute.

**Step 4: Remove cancel_at_period_end from fixtures**

In `test/fixtures/subscriptions.yml`, remove `cancel_at_period_end: true` from the canceling_subscription fixture (keep `cancel_at`).

**Step 5: Run tests**

Run:
```bash
bin/rails test
```

Expected: All tests PASS

**Step 6: Generate migration to remove column**

Run:
```bash
bin/rails generate migration RemoveCancelAtPeriodEndFromSubscriptions
```

**Step 7: Edit migration**

Edit the generated migration file:

```ruby
class RemoveCancelAtPeriodEndFromSubscriptions < ActiveRecord::Migration[8.1]
  def change
    remove_column :subscriptions, :cancel_at_period_end, :boolean, default: false, null: false
  end
end
```

**Step 8: Run migration**

Run:
```bash
bin/rails db:migrate
```

Expected: Migration runs successfully

**Step 9: Run full test suite**

Run:
```bash
bin/rails test
```

Expected: All tests PASS

**Step 10: Commit**

```bash
git add -A
git commit -m "Remove cancel_at_period_end column, replaced by cancel_at"
```

---

## Task 8: Resync Production Subscriptions

**After deploying:**

Run in production:
```bash
kamal app exec --reuse 'bin/rails subscriptions:resync_all'
```

Expected: All subscriptions resynced with correct cancel_at values

---

## Verification Checklist

- [ ] `cancel_at` column exists in subscriptions table
- [ ] `SyncsSubscription` correctly populates `cancel_at` from Stripe's `cancel_at` or derives it from `cancel_at_period_end`
- [ ] `Subscription#canceling?` returns true when `cancel_at` is present
- [ ] Billing page shows correct "Ends on" date for canceling subscriptions
- [ ] `cancel_at_period_end` column is removed
- [ ] All tests pass
- [ ] Production subscriptions resynced
