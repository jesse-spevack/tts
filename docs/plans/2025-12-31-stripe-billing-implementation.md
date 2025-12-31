# Stripe Billing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Stripe subscription billing so free users can upgrade to Premium ($9/mo or $89/yr).

**Architecture:** Stripe Checkout for payment, Customer Portal for management, webhooks sync subscription state. User tier derived from subscription status, not stored on user.

**Tech Stack:** Rails 8.1, Stripe gem, Stripe Checkout, Stripe Customer Portal, Stripe Webhooks

---

## Task 1: Add Stripe Gem

**Files:**
- Modify: `Gemfile:42` (after bcrypt)

**Step 1: Add stripe gem to Gemfile**

Add after the `gem "bcrypt"` line:

```ruby
gem "stripe"
```

**Step 2: Install the gem**

Run: `bundle install`

Expected: Stripe gem installed successfully

**Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add stripe gem"
```

---

## Task 2: Create Subscriptions Migration

**Files:**
- Create: `db/migrate/XXXXXX_create_subscriptions.rb`

**Step 1: Generate migration**

Run: `bin/rails generate migration CreateSubscriptions`

**Step 2: Write the migration**

```ruby
class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :stripe_customer_id, null: false
      t.string :stripe_subscription_id, null: false
      t.string :stripe_price_id, null: false
      t.integer :status, null: false, default: 0
      t.datetime :current_period_end, null: false
      t.timestamps
    end

    add_index :subscriptions, :stripe_customer_id, unique: true
    add_index :subscriptions, :stripe_subscription_id, unique: true
  end
end
```

**Step 3: Run migration**

Run: `bin/rails db:migrate`

Expected: Migration runs successfully

**Step 4: Verify schema**

Run: `bin/rails db:schema:dump && grep -A 15 "create_table \"subscriptions\"" db/schema.rb`

Expected: See subscriptions table with all columns

**Step 5: Commit**

```bash
git add db/migrate/*_create_subscriptions.rb db/schema.rb
git commit -m "feat: add subscriptions table"
```

---

## Task 3: Add Account Type to Users Migration

**Files:**
- Create: `db/migrate/XXXXXX_add_account_type_to_users.rb`

**Step 1: Generate migration**

Run: `bin/rails generate migration AddAccountTypeToUsers`

**Step 2: Write the migration**

```ruby
class AddAccountTypeToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :account_type, :integer, default: 0, null: false

    # Migrate existing unlimited users
    execute <<-SQL
      UPDATE users SET account_type = 2 WHERE tier = 2
    SQL

    remove_column :users, :tier
  end

  def down
    add_column :users, :tier, :integer, default: 0

    # Restore unlimited users
    execute <<-SQL
      UPDATE users SET tier = 2 WHERE account_type = 2
    SQL

    remove_column :users, :account_type
  end
end
```

**Step 3: Run migration**

Run: `bin/rails db:migrate`

Expected: Migration runs successfully

**Step 4: Verify schema**

Run: `grep "account_type" db/schema.rb`

Expected: See `t.integer "account_type", default: 0, null: false`

**Step 5: Commit**

```bash
git add db/migrate/*_add_account_type_to_users.rb db/schema.rb
git commit -m "feat: replace users.tier with account_type enum"
```

---

## Task 4: Create Subscription Model

**Files:**
- Create: `app/models/subscription.rb`
- Create: `test/models/subscription_test.rb`
- Create: `test/fixtures/subscriptions.yml`

**Step 1: Write the failing test**

Create `test/models/subscription_test.rb`:

```ruby
require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  test "status enum has correct values" do
    assert_equal({ "active" => 0, "past_due" => 1, "canceled" => 2 }, Subscription.statuses)
  end

  test "belongs to user" do
    subscription = subscriptions(:active_subscription)
    assert_equal users(:subscriber), subscription.user
  end

  test "active? returns true for active subscriptions" do
    subscription = subscriptions(:active_subscription)
    assert subscription.active?
  end

  test "active? returns false for canceled subscriptions" do
    subscription = subscriptions(:canceled_subscription)
    refute subscription.active?
  end
end
```

**Step 2: Create fixtures**

Create `test/fixtures/subscriptions.yml`:

```yaml
active_subscription:
  user: subscriber
  stripe_customer_id: cus_test_active
  stripe_subscription_id: sub_test_active
  stripe_price_id: price_monthly
  status: 0
  current_period_end: <%= 1.month.from_now %>

canceled_subscription:
  user: canceled_subscriber
  stripe_customer_id: cus_test_canceled
  stripe_subscription_id: sub_test_canceled
  stripe_price_id: price_monthly
  status: 2
  current_period_end: <%= 1.day.ago %>

past_due_subscription:
  user: past_due_subscriber
  stripe_customer_id: cus_test_past_due
  stripe_subscription_id: sub_test_past_due
  stripe_price_id: price_monthly
  status: 1
  current_period_end: <%= 1.week.from_now %>
```

**Step 3: Update users fixtures**

Add to `test/fixtures/users.yml`:

```yaml
subscriber:
  email_address: subscriber@example.com
  account_type: 0

canceled_subscriber:
  email_address: canceled@example.com
  account_type: 0

past_due_subscriber:
  email_address: pastdue@example.com
  account_type: 0
```

**Step 4: Run test to verify it fails**

Run: `bin/rails test test/models/subscription_test.rb`

Expected: FAIL (Subscription model doesn't exist)

**Step 5: Write the model**

Create `app/models/subscription.rb`:

```ruby
class Subscription < ApplicationRecord
  belongs_to :user

  enum :status, { active: 0, past_due: 1, canceled: 2 }

  validates :stripe_customer_id, presence: true, uniqueness: true
  validates :stripe_subscription_id, presence: true, uniqueness: true
  validates :stripe_price_id, presence: true
  validates :current_period_end, presence: true
end
```

**Step 6: Run test to verify it passes**

Run: `bin/rails test test/models/subscription_test.rb`

Expected: PASS

**Step 7: Commit**

```bash
git add app/models/subscription.rb test/models/subscription_test.rb test/fixtures/subscriptions.yml test/fixtures/users.yml
git commit -m "feat: add Subscription model with status enum"
```

---

## Task 5: Update User Model

**Files:**
- Modify: `app/models/user.rb`
- Modify: `test/models/user_test.rb`
- Modify: `test/fixtures/users.yml`

**Step 1: Write the failing tests**

Add to `test/models/user_test.rb`:

```ruby
class UserTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "account_type enum has correct values" do
    assert_equal({ "standard" => 0, "complimentary" => 1, "unlimited" => 2 }, User.account_types)
  end

  test "premium? returns true for user with active subscription" do
    user = users(:subscriber)
    assert user.premium?
  end

  test "premium? returns false for user without subscription" do
    user = users(:free_user)
    refute user.premium?
  end

  test "premium? returns true for complimentary user" do
    user = users(:complimentary_user)
    assert user.premium?
  end

  test "premium? returns true for unlimited user" do
    user = users(:unlimited_user)
    assert user.premium?
  end

  test "premium? returns false for user with canceled subscription" do
    user = users(:canceled_subscriber)
    refute user.premium?
  end

  test "free? returns true for standard user without subscription" do
    user = users(:free_user)
    assert user.free?
  end

  test "free? returns false for user with active subscription" do
    user = users(:subscriber)
    refute user.free?
  end

  test "free? returns false for complimentary user" do
    user = users(:complimentary_user)
    refute user.free?
  end

  test "free? returns false for unlimited user" do
    user = users(:unlimited_user)
    refute user.free?
  end
end
```

**Step 2: Update users fixtures**

Replace `test/fixtures/users.yml` entirely:

```yaml
one:
  email_address: user1@example.com
  account_type: 0

two:
  email_address: user2@example.com
  account_type: 0

free_user:
  email_address: free@example.com
  account_type: 0

complimentary_user:
  email_address: complimentary@example.com
  account_type: 1

unlimited_user:
  email_address: unlimited@example.com
  account_type: 2

admin_user:
  email_address: admin@example.com
  account_type: 0
  admin: true

jesse:
  email_address: jesse@example.com
  account_type: 0

subscriber:
  email_address: subscriber@example.com
  account_type: 0

canceled_subscriber:
  email_address: canceled@example.com
  account_type: 0

past_due_subscriber:
  email_address: pastdue@example.com
  account_type: 0
```

**Step 3: Run test to verify it fails**

Run: `bin/rails test test/models/user_test.rb`

Expected: FAIL (tier enum still exists, premium?/free? methods wrong)

**Step 4: Update the User model**

Replace `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :podcast_memberships, dependent: :destroy
  has_many :podcasts, through: :podcast_memberships
  has_many :episodes, dependent: :destroy
  has_many :sent_messages, dependent: :destroy
  has_one :subscription, dependent: :destroy

  enum :account_type, { standard: 0, complimentary: 1, unlimited: 2 }, default: :standard

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :voice_preference, inclusion: { in: Voice::ALL }, allow_nil: true

  scope :with_valid_auth_token, -> {
    where.not(auth_token: nil)
         .where("auth_token_expires_at > ?", Time.current)
  }

  def premium?
    subscription&.active? || complimentary? || unlimited?
  end

  def free?
    standard? && !subscription&.active?
  end

  def voice
    if voice_preference.present?
      voice_data = Voice.find(voice_preference)
      return voice_data[:google_voice] if voice_data
    end
    unlimited? ? Voice::DEFAULT_CHIRP : Voice::DEFAULT_STANDARD
  end

  def available_voices
    AppConfig::Tiers.voices_for(effective_tier)
  end

  def email
    email_address
  end

  private

  def effective_tier
    return "unlimited" if unlimited?
    return "premium" if premium?
    "free"
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rails test test/models/user_test.rb`

Expected: PASS

**Step 6: Commit**

```bash
git add app/models/user.rb test/models/user_test.rb test/fixtures/users.yml
git commit -m "feat: update User model with account_type enum and premium?/free? methods"
```

---

## Task 6: Update AppConfig for Stripe

**Files:**
- Modify: `app/models/app_config.rb`
- Modify: `test/models/app_config_test.rb`

**Step 1: Write the failing test**

Add to `test/models/app_config_test.rb`:

```ruby
class AppConfigTest < ActiveSupport::TestCase
  # ... existing tests ...

  test "Stripe module has price constants" do
    assert_equal "test_price_monthly", AppConfig::Stripe::PRICE_ID_MONTHLY
    assert_equal "test_price_annual", AppConfig::Stripe::PRICE_ID_ANNUAL
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/app_config_test.rb`

Expected: FAIL (AppConfig::Stripe doesn't exist)

**Step 3: Update AppConfig**

Add to `app/models/app_config.rb` before the final `end`:

```ruby
  module Stripe
    PRICE_ID_MONTHLY = ENV.fetch("STRIPE_PRICE_ID_MONTHLY", "test_price_monthly")
    PRICE_ID_ANNUAL = ENV.fetch("STRIPE_PRICE_ID_ANNUAL", "test_price_annual")
    WEBHOOK_SECRET = ENV.fetch("STRIPE_WEBHOOK_SECRET", "test_webhook_secret")
  end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/app_config_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add app/models/app_config.rb test/models/app_config_test.rb
git commit -m "feat: add Stripe configuration to AppConfig"
```

---

## Task 7: Create Stripe Initializer

**Files:**
- Create: `config/initializers/stripe.rb`

**Step 1: Create the initializer**

Create `config/initializers/stripe.rb`:

```ruby
Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY", nil)
```

**Step 2: Verify Rails loads without error**

Run: `bin/rails runner "puts Stripe.api_key.inspect"`

Expected: Outputs `nil` (no error)

**Step 3: Commit**

```bash
git add config/initializers/stripe.rb
git commit -m "feat: add Stripe initializer"
```

---

## Task 8: Create CreatesCheckoutSession Service

**Files:**
- Create: `app/services/creates_checkout_session.rb`
- Create: `test/services/creates_checkout_session_test.rb`

**Step 1: Write the failing test**

Create `test/services/creates_checkout_session_test.rb`:

```ruby
require "test_helper"

class CreatesCheckoutSessionTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
  end

  test "creates checkout session and returns URL" do
    mock_customer = OpenStruct.new(id: "cus_test123")
    mock_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    Stripe::Customer.stub :create, mock_customer do
      Stripe::Customer.stub :list, OpenStruct.new(data: []) do
        Stripe::Checkout::Session.stub :create, mock_session do
          result = CreatesCheckoutSession.call(
            user: @user,
            price_id: "price_test",
            success_url: "https://example.com/success",
            cancel_url: "https://example.com/cancel"
          )

          assert result.success?
          assert_equal "https://checkout.stripe.com/test", result.data
        end
      end
    end
  end

  test "reuses existing Stripe customer" do
    mock_customer = OpenStruct.new(id: "cus_existing")
    mock_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    Stripe::Customer.stub :list, OpenStruct.new(data: [mock_customer]) do
      Stripe::Checkout::Session.stub :create, mock_session do
        result = CreatesCheckoutSession.call(
          user: @user,
          price_id: "price_test",
          success_url: "https://example.com/success",
          cancel_url: "https://example.com/cancel"
        )

        assert result.success?
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/creates_checkout_session_test.rb`

Expected: FAIL (service doesn't exist)

**Step 3: Write the service**

Create `app/services/creates_checkout_session.rb`:

```ruby
class CreatesCheckoutSession
  def self.call(user:, price_id:, success_url:, cancel_url:)
    new(user:, price_id:, success_url:, cancel_url:).call
  end

  def initialize(user:, price_id:, success_url:, cancel_url:)
    @user = user
    @price_id = price_id
    @success_url = success_url
    @cancel_url = cancel_url
  end

  def call
    customer = find_or_create_customer
    session = create_checkout_session(customer)
    Result.success(session.url)
  rescue Stripe::StripeError => e
    Result.failure("Stripe error: #{e.message}")
  end

  private

  attr_reader :user, :price_id, :success_url, :cancel_url

  def find_or_create_customer
    existing = Stripe::Customer.list(email: user.email_address, limit: 1)
    return existing.data.first if existing.data.any?

    Stripe::Customer.create(
      email: user.email_address,
      metadata: { user_id: user.id }
    )
  end

  def create_checkout_session(customer)
    Stripe::Checkout::Session.create(
      customer: customer.id,
      mode: "subscription",
      line_items: [{ price: price_id, quantity: 1 }],
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: { user_id: user.id }
    )
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/creates_checkout_session_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add app/services/creates_checkout_session.rb test/services/creates_checkout_session_test.rb
git commit -m "feat: add CreatesCheckoutSession service"
```

---

## Task 9: Create CreatesBillingPortalSession Service

**Files:**
- Create: `app/services/creates_billing_portal_session.rb`
- Create: `test/services/creates_billing_portal_session_test.rb`

**Step 1: Write the failing test**

Create `test/services/creates_billing_portal_session_test.rb`:

```ruby
require "test_helper"

class CreatesBillingPortalSessionTest < ActiveSupport::TestCase
  test "creates portal session and returns URL" do
    mock_session = OpenStruct.new(url: "https://billing.stripe.com/test")

    Stripe::BillingPortal::Session.stub :create, mock_session do
      result = CreatesBillingPortalSession.call(
        stripe_customer_id: "cus_test123",
        return_url: "https://example.com/billing"
      )

      assert result.success?
      assert_equal "https://billing.stripe.com/test", result.data
    end
  end

  test "returns failure on Stripe error" do
    error = Stripe::InvalidRequestError.new("Customer not found", "customer")

    Stripe::BillingPortal::Session.stub :create, ->(*) { raise error } do
      result = CreatesBillingPortalSession.call(
        stripe_customer_id: "cus_invalid",
        return_url: "https://example.com/billing"
      )

      refute result.success?
      assert_match(/Stripe error/, result.error)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/creates_billing_portal_session_test.rb`

Expected: FAIL (service doesn't exist)

**Step 3: Write the service**

Create `app/services/creates_billing_portal_session.rb`:

```ruby
class CreatesBillingPortalSession
  def self.call(stripe_customer_id:, return_url:)
    new(stripe_customer_id:, return_url:).call
  end

  def initialize(stripe_customer_id:, return_url:)
    @stripe_customer_id = stripe_customer_id
    @return_url = return_url
  end

  def call
    session = Stripe::BillingPortal::Session.create(
      customer: stripe_customer_id,
      return_url: return_url
    )
    Result.success(session.url)
  rescue Stripe::StripeError => e
    Result.failure("Stripe error: #{e.message}")
  end

  private

  attr_reader :stripe_customer_id, :return_url
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/creates_billing_portal_session_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add app/services/creates_billing_portal_session.rb test/services/creates_billing_portal_session_test.rb
git commit -m "feat: add CreatesBillingPortalSession service"
```

---

## Task 10: Create SyncsSubscription Service

**Files:**
- Create: `app/services/syncs_subscription.rb`
- Create: `test/services/syncs_subscription_test.rb`

**Step 1: Write the failing test**

Create `test/services/syncs_subscription_test.rb`:

```ruby
require "test_helper"

class SyncsSubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = users(:free_user)
  end

  test "creates new subscription for active Stripe subscription" do
    stripe_subscription = mock_stripe_subscription(
      id: "sub_new",
      customer: "cus_new",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    Stripe::Subscription.stub :retrieve, stripe_subscription do
      Stripe::Customer.stub :retrieve, OpenStruct.new(metadata: { "user_id" => @user.id.to_s }) do
        result = SyncsSubscription.call(stripe_subscription_id: "sub_new")

        assert result.success?
        subscription = result.data
        assert_equal @user, subscription.user
        assert_equal "cus_new", subscription.stripe_customer_id
        assert subscription.active?
      end
    end
  end

  test "updates existing subscription" do
    subscription = Subscription.create!(
      user: @user,
      stripe_customer_id: "cus_existing",
      stripe_subscription_id: "sub_existing",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.week.from_now
    )

    stripe_subscription = mock_stripe_subscription(
      id: "sub_existing",
      customer: "cus_existing",
      status: "past_due",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    Stripe::Subscription.stub :retrieve, stripe_subscription do
      result = SyncsSubscription.call(stripe_subscription_id: "sub_existing")

      assert result.success?
      subscription.reload
      assert subscription.past_due?
    end
  end

  test "sets canceled status for canceled subscription" do
    stripe_subscription = mock_stripe_subscription(
      id: "sub_canceled",
      customer: "cus_canceled",
      status: "canceled",
      price_id: "price_monthly",
      current_period_end: 1.day.ago.to_i
    )

    Stripe::Subscription.stub :retrieve, stripe_subscription do
      Stripe::Customer.stub :retrieve, OpenStruct.new(metadata: { "user_id" => @user.id.to_s }) do
        result = SyncsSubscription.call(stripe_subscription_id: "sub_canceled")

        assert result.success?
        assert result.data.canceled?
      end
    end
  end

  test "maps trialing status to active" do
    stripe_subscription = mock_stripe_subscription(
      id: "sub_trial",
      customer: "cus_trial",
      status: "trialing",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    Stripe::Subscription.stub :retrieve, stripe_subscription do
      Stripe::Customer.stub :retrieve, OpenStruct.new(metadata: { "user_id" => @user.id.to_s }) do
        result = SyncsSubscription.call(stripe_subscription_id: "sub_trial")

        assert result.success?
        assert result.data.active?
      end
    end
  end

  private

  def mock_stripe_subscription(id:, customer:, status:, price_id:, current_period_end:)
    items = OpenStruct.new(data: [OpenStruct.new(price: OpenStruct.new(id: price_id))])
    OpenStruct.new(
      id: id,
      customer: customer,
      status: status,
      items: items,
      current_period_end: current_period_end
    )
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/syncs_subscription_test.rb`

Expected: FAIL (service doesn't exist)

**Step 3: Write the service**

Create `app/services/syncs_subscription.rb`:

```ruby
class SyncsSubscription
  def self.call(stripe_subscription_id:)
    new(stripe_subscription_id:).call
  end

  def initialize(stripe_subscription_id:)
    @stripe_subscription_id = stripe_subscription_id
  end

  def call
    stripe_subscription = Stripe::Subscription.retrieve(stripe_subscription_id)

    subscription = Subscription.find_or_initialize_by(
      stripe_subscription_id: stripe_subscription.id
    )

    subscription.update!(
      user: find_user(subscription, stripe_subscription.customer),
      stripe_customer_id: stripe_subscription.customer,
      status: map_status(stripe_subscription.status),
      stripe_price_id: stripe_subscription.items.data.first.price.id,
      current_period_end: Time.at(stripe_subscription.current_period_end)
    )

    Result.success(subscription)
  rescue Stripe::StripeError => e
    Result.failure("Stripe API error: #{e.message}")
  end

  private

  attr_reader :stripe_subscription_id

  def find_user(subscription, stripe_customer_id)
    return subscription.user if subscription.persisted?

    customer = Stripe::Customer.retrieve(stripe_customer_id)
    User.find(customer.metadata["user_id"])
  end

  def map_status(stripe_status)
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

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/syncs_subscription_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add app/services/syncs_subscription.rb test/services/syncs_subscription_test.rb
git commit -m "feat: add SyncsSubscription service with Stripe API re-fetch"
```

---

## Task 11: Create RoutesStripeWebhook Service

**Files:**
- Create: `app/services/routes_stripe_webhook.rb`
- Create: `test/services/routes_stripe_webhook_test.rb`

**Step 1: Write the failing test**

Create `test/services/routes_stripe_webhook_test.rb`:

```ruby
require "test_helper"

class RoutesStripeWebhookTest < ActiveSupport::TestCase
  test "routes checkout.session.completed to CreatesSubscriptionFromCheckout" do
    event = OpenStruct.new(
      type: "checkout.session.completed",
      data: OpenStruct.new(object: OpenStruct.new(id: "cs_test"))
    )

    called = false
    CreatesSubscriptionFromCheckout.stub :call, ->(**) { called = true; Result.success } do
      RoutesStripeWebhook.call(event: event)
    end

    assert called, "Expected CreatesSubscriptionFromCheckout to be called"
  end

  test "routes customer.subscription.updated to SyncsSubscription" do
    event = OpenStruct.new(
      type: "customer.subscription.updated",
      data: OpenStruct.new(object: OpenStruct.new(id: "sub_test"))
    )

    called_with = nil
    SyncsSubscription.stub :call, ->(stripe_subscription_id:) { called_with = stripe_subscription_id; Result.success } do
      RoutesStripeWebhook.call(event: event)
    end

    assert_equal "sub_test", called_with
  end

  test "routes customer.subscription.deleted to SyncsSubscription" do
    event = OpenStruct.new(
      type: "customer.subscription.deleted",
      data: OpenStruct.new(object: OpenStruct.new(id: "sub_test"))
    )

    called_with = nil
    SyncsSubscription.stub :call, ->(stripe_subscription_id:) { called_with = stripe_subscription_id; Result.success } do
      RoutesStripeWebhook.call(event: event)
    end

    assert_equal "sub_test", called_with
  end

  test "routes invoice.payment_failed to SyncsSubscription" do
    event = OpenStruct.new(
      type: "invoice.payment_failed",
      data: OpenStruct.new(object: OpenStruct.new(subscription: "sub_test"))
    )

    called_with = nil
    SyncsSubscription.stub :call, ->(stripe_subscription_id:) { called_with = stripe_subscription_id; Result.success } do
      RoutesStripeWebhook.call(event: event)
    end

    assert_equal "sub_test", called_with
  end

  test "ignores unhandled event types" do
    event = OpenStruct.new(
      type: "customer.created",
      data: OpenStruct.new(object: OpenStruct.new(id: "cus_test"))
    )

    result = RoutesStripeWebhook.call(event: event)
    assert result.success?
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/routes_stripe_webhook_test.rb`

Expected: FAIL (service doesn't exist)

**Step 3: Write the service**

Create `app/services/routes_stripe_webhook.rb`:

```ruby
class RoutesStripeWebhook
  def self.call(event:)
    new(event:).call
  end

  def initialize(event:)
    @event = event
  end

  def call
    case event.type
    when "checkout.session.completed"
      CreatesSubscriptionFromCheckout.call(session: event.data.object)
    when "customer.subscription.updated", "customer.subscription.deleted"
      SyncsSubscription.call(stripe_subscription_id: event.data.object.id)
    when "invoice.payment_failed"
      SyncsSubscription.call(stripe_subscription_id: event.data.object.subscription)
    else
      Result.success
    end
  end

  private

  attr_reader :event
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/routes_stripe_webhook_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add app/services/routes_stripe_webhook.rb test/services/routes_stripe_webhook_test.rb
git commit -m "feat: add RoutesStripeWebhook service"
```

---

## Task 12: Create CreatesSubscriptionFromCheckout Service

**Files:**
- Create: `app/services/creates_subscription_from_checkout.rb`
- Create: `test/services/creates_subscription_from_checkout_test.rb`

**Step 1: Write the failing test**

Create `test/services/creates_subscription_from_checkout_test.rb`:

```ruby
require "test_helper"

class CreatesSubscriptionFromCheckoutTest < ActiveSupport::TestCase
  test "syncs subscription from checkout session" do
    session = OpenStruct.new(subscription: "sub_from_checkout")

    synced = false
    SyncsSubscription.stub :call, ->(stripe_subscription_id:) {
      synced = stripe_subscription_id == "sub_from_checkout"
      Result.success
    } do
      result = CreatesSubscriptionFromCheckout.call(session: session)
      assert result.success?
    end

    assert synced, "Expected SyncsSubscription to be called with subscription ID"
  end

  test "returns failure if no subscription in session" do
    session = OpenStruct.new(subscription: nil)

    result = CreatesSubscriptionFromCheckout.call(session: session)

    refute result.success?
    assert_match(/No subscription/, result.error)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/creates_subscription_from_checkout_test.rb`

Expected: FAIL (service doesn't exist)

**Step 3: Write the service**

Create `app/services/creates_subscription_from_checkout.rb`:

```ruby
class CreatesSubscriptionFromCheckout
  def self.call(session:)
    new(session:).call
  end

  def initialize(session:)
    @session = session
  end

  def call
    return Result.failure("No subscription in checkout session") unless session.subscription

    SyncsSubscription.call(stripe_subscription_id: session.subscription)
  end

  private

  attr_reader :session
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/creates_subscription_from_checkout_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add app/services/creates_subscription_from_checkout.rb test/services/creates_subscription_from_checkout_test.rb
git commit -m "feat: add CreatesSubscriptionFromCheckout service"
```

---

## Task 13: Add Billing Routes

**Files:**
- Modify: `config/routes.rb`

**Step 1: Update routes**

Add to `config/routes.rb` after the settings resource:

```ruby
  # Billing
  get "pricing", to: redirect("/#pricing")
  get "billing", to: "billing#show"
  post "billing/portal", to: "billing#portal"
  post "checkout", to: "checkout#create"
  get "checkout/success", to: "checkout#success"
  get "checkout/cancel", to: "checkout#cancel"
  post "webhooks/stripe", to: "webhooks#stripe"
```

**Step 2: Verify routes**

Run: `bin/rails routes | grep -E "billing|checkout|webhook|pricing"`

Expected: See all billing-related routes listed

**Step 3: Commit**

```bash
git add config/routes.rb
git commit -m "feat: add billing, checkout, and webhook routes"
```

---

## Task 14: Create WebhooksController

**Files:**
- Create: `app/controllers/webhooks_controller.rb`
- Create: `test/controllers/webhooks_controller_test.rb`

**Step 1: Write the failing test**

Create `test/controllers/webhooks_controller_test.rb`:

```ruby
require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  test "returns 400 when signature verification fails" do
    Stripe::Webhook.stub :construct_event, ->(*) { raise Stripe::SignatureVerificationError.new("bad sig", "sig") } do
      post webhooks_stripe_path,
        params: "{}",
        headers: { "Stripe-Signature" => "bad_signature", "CONTENT_TYPE" => "application/json" }

      assert_response :bad_request
    end
  end

  test "returns 200 and routes event on success" do
    event = OpenStruct.new(type: "customer.created", data: OpenStruct.new(object: {}))

    Stripe::Webhook.stub :construct_event, event do
      RoutesStripeWebhook.stub :call, Result.success do
        post webhooks_stripe_path,
          params: "{}",
          headers: { "Stripe-Signature" => "valid_signature", "CONTENT_TYPE" => "application/json" }

        assert_response :success
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/webhooks_controller_test.rb`

Expected: FAIL (controller doesn't exist)

**Step 3: Write the controller**

Create `app/controllers/webhooks_controller.rb`:

```ruby
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :stripe

  def stripe
    payload = request.body.read
    signature = request.env["HTTP_STRIPE_SIGNATURE"]

    event = Stripe::Webhook.construct_event(
      payload, signature, AppConfig::Stripe::WEBHOOK_SECRET
    )

    RoutesStripeWebhook.call(event: event)
    head :ok
  rescue Stripe::SignatureVerificationError
    head :bad_request
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/webhooks_controller_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add app/controllers/webhooks_controller.rb test/controllers/webhooks_controller_test.rb
git commit -m "feat: add WebhooksController for Stripe webhooks"
```

---

## Task 15: Create CheckoutController

**Files:**
- Create: `app/controllers/checkout_controller.rb`
- Create: `app/views/checkout/success.html.erb`
- Create: `test/controllers/checkout_controller_test.rb`

**Step 1: Write the failing test**

Create `test/controllers/checkout_controller_test.rb`:

```ruby
require "test_helper"

class CheckoutControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:free_user)
    login_as(@user)
  end

  test "create redirects to Stripe checkout" do
    CreatesCheckoutSession.stub :call, Result.success("https://checkout.stripe.com/test") do
      post checkout_path, params: { price_id: AppConfig::Stripe::PRICE_ID_MONTHLY }

      assert_redirected_to "https://checkout.stripe.com/test"
    end
  end

  test "create with invalid price redirects back with error" do
    post checkout_path, params: { price_id: "invalid" }

    assert_redirected_to billing_path
    assert_equal "Invalid price selected", flash[:alert]
  end

  test "create requires authentication" do
    logout
    post checkout_path, params: { price_id: AppConfig::Stripe::PRICE_ID_MONTHLY }

    assert_redirected_to root_path
  end

  test "success page renders" do
    get checkout_success_path

    assert_response :success
  end

  test "cancel redirects to billing" do
    get checkout_cancel_path

    assert_redirected_to billing_path
  end

  private

  def login_as(user)
    session = user.sessions.create!(ip_address: "127.0.0.1", user_agent: "Test")
    cookies.signed[:session_id] = session.id
  end

  def logout
    cookies.delete(:session_id)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/checkout_controller_test.rb`

Expected: FAIL (controller doesn't exist)

**Step 3: Write the controller**

Create `app/controllers/checkout_controller.rb`:

```ruby
class CheckoutController < ApplicationController
  before_action :require_authentication

  def create
    price_id = params[:price_id]

    unless valid_price?(price_id)
      redirect_to billing_path, alert: "Invalid price selected"
      return
    end

    result = CreatesCheckoutSession.call(
      user: Current.user,
      price_id: price_id,
      success_url: checkout_success_url,
      cancel_url: checkout_cancel_url
    )

    if result.success?
      redirect_to result.data, allow_other_host: true
    else
      redirect_to billing_path, alert: result.error
    end
  end

  def success
  end

  def cancel
    redirect_to billing_path
  end

  private

  def valid_price?(price_id)
    [AppConfig::Stripe::PRICE_ID_MONTHLY, AppConfig::Stripe::PRICE_ID_ANNUAL].include?(price_id)
  end
end
```

**Step 4: Create success view**

Create `app/views/checkout/success.html.erb`:

```erb
<div class="max-w-xl mx-auto px-4 py-16 text-center">
  <div class="mb-6">
    <svg class="w-16 h-16 mx-auto text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
    </svg>
  </div>

  <h1 class="text-3xl font-bold text-gray-900 dark:text-white mb-4">
    Welcome to Premium!
  </h1>

  <p class="text-lg text-gray-600 dark:text-gray-400 mb-8">
    Your subscription is now active. You have unlimited episodes and 50,000 characters per episode.
  </p>

  <%= link_to "Start creating episodes", new_episode_path,
    class: "inline-flex items-center px-6 py-3 bg-indigo-600 text-white font-medium rounded-lg hover:bg-indigo-700" %>
</div>
```

**Step 5: Run test to verify it passes**

Run: `bin/rails test test/controllers/checkout_controller_test.rb`

Expected: PASS

**Step 6: Commit**

```bash
git add app/controllers/checkout_controller.rb app/views/checkout/success.html.erb test/controllers/checkout_controller_test.rb
git commit -m "feat: add CheckoutController with success and cancel pages"
```

---

## Task 16: Create BillingController

**Files:**
- Create: `app/controllers/billing_controller.rb`
- Create: `app/views/billing/show.html.erb`
- Create: `app/views/billing/_upgrade_options.html.erb`
- Create: `test/controllers/billing_controller_test.rb`

**Step 1: Write the failing test**

Create `test/controllers/billing_controller_test.rb`:

```ruby
require "test_helper"

class BillingControllerTest < ActionDispatch::IntegrationTest
  test "show requires authentication" do
    get billing_path
    assert_redirected_to root_path
  end

  test "show renders for free user" do
    login_as(users(:free_user))
    get billing_path
    assert_response :success
  end

  test "show renders for premium user" do
    login_as(users(:subscriber))
    get billing_path
    assert_response :success
  end

  test "portal redirects to Stripe" do
    user = users(:subscriber)
    login_as(user)

    CreatesBillingPortalSession.stub :call, Result.success("https://billing.stripe.com/test") do
      post billing_portal_path
      assert_redirected_to "https://billing.stripe.com/test"
    end
  end

  test "portal requires subscription" do
    login_as(users(:free_user))
    post billing_portal_path
    assert_redirected_to billing_path
    assert_equal "No active subscription", flash[:alert]
  end

  private

  def login_as(user)
    session = user.sessions.create!(ip_address: "127.0.0.1", user_agent: "Test")
    cookies.signed[:session_id] = session.id
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/billing_controller_test.rb`

Expected: FAIL (controller doesn't exist)

**Step 3: Write the controller**

Create `app/controllers/billing_controller.rb`:

```ruby
class BillingController < ApplicationController
  before_action :require_authentication

  def show
    @subscription = Current.user.subscription
    @usage = EpisodeUsage.current_for(Current.user) if Current.user.free?
  end

  def portal
    subscription = Current.user.subscription

    unless subscription&.stripe_customer_id
      redirect_to billing_path, alert: "No active subscription"
      return
    end

    result = CreatesBillingPortalSession.call(
      stripe_customer_id: subscription.stripe_customer_id,
      return_url: billing_url
    )

    if result.success?
      redirect_to result.data, allow_other_host: true
    else
      redirect_to billing_path, alert: result.error
    end
  end
end
```

**Step 4: Create the view**

Create `app/views/billing/show.html.erb`:

```erb
<div class="max-w-2xl mx-auto px-4 py-8">
  <h1 class="text-3xl font-bold text-gray-900 dark:text-white mb-8">Billing</h1>

  <% if Current.user.unlimited? %>
    <div class="bg-purple-50 dark:bg-purple-900/20 rounded-lg p-6 mb-6">
      <h2 class="text-xl font-semibold text-purple-900 dark:text-purple-100 mb-2">Unlimited Plan</h2>
      <p class="text-purple-700 dark:text-purple-300">You have unlimited access with no restrictions.</p>
    </div>

  <% elsif Current.user.complimentary? %>
    <div class="bg-green-50 dark:bg-green-900/20 rounded-lg p-6 mb-6">
      <h2 class="text-xl font-semibold text-green-900 dark:text-green-100 mb-2">Premium (Complimentary)</h2>
      <p class="text-green-700 dark:text-green-300">You have complimentary premium access.</p>
    </div>

  <% elsif @subscription&.active? %>
    <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6 mb-6">
      <h2 class="text-xl font-semibold text-gray-900 dark:text-white mb-2">Premium Plan</h2>
      <p class="text-gray-600 dark:text-gray-400 mb-4">
        Renews on <%= @subscription.current_period_end.strftime("%B %d, %Y") %>
      </p>
      <%= button_to "Manage Subscription", billing_portal_path,
        class: "px-4 py-2 bg-gray-200 dark:bg-gray-700 text-gray-800 dark:text-gray-200 rounded-lg hover:bg-gray-300 dark:hover:bg-gray-600" %>
    </div>

  <% elsif @subscription&.past_due? %>
    <div class="bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800 rounded-lg p-6 mb-6">
      <h2 class="text-xl font-semibold text-yellow-900 dark:text-yellow-100 mb-2">Payment Failed</h2>
      <p class="text-yellow-700 dark:text-yellow-300 mb-4">Please update your payment method to restore Premium access.</p>
      <%= button_to "Fix Payment", billing_portal_path,
        class: "px-4 py-2 bg-yellow-600 text-white rounded-lg hover:bg-yellow-700" %>
    </div>

  <% elsif @subscription&.canceled? %>
    <div class="bg-gray-50 dark:bg-gray-800 rounded-lg p-6 mb-6">
      <h2 class="text-xl font-semibold text-gray-900 dark:text-white mb-2">Subscription Ended</h2>
      <p class="text-gray-600 dark:text-gray-400 mb-4">
        Your subscription ended on <%= @subscription.current_period_end.strftime("%B %d, %Y") %>.
      </p>
    </div>
    <%= render "upgrade_options" %>

  <% else %>
    <div class="bg-gray-50 dark:bg-gray-800 rounded-lg p-6 mb-6">
      <h2 class="text-xl font-semibold text-gray-900 dark:text-white mb-2">Free Plan</h2>
      <% if @usage %>
        <p class="text-gray-600 dark:text-gray-400 mb-4">
          <%= @usage.episode_count %> of <%= AppConfig::Tiers::FREE_MONTHLY_EPISODES %> episodes used this month
        </p>
      <% end %>
    </div>
    <%= render "upgrade_options" %>
  <% end %>
</div>
```

**Step 5: Create the upgrade options partial**

Create `app/views/billing/_upgrade_options.html.erb`:

```erb
<div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
  <h2 class="text-xl font-semibold text-gray-900 dark:text-white mb-4">Upgrade to Premium</h2>

  <div class="space-y-4 mb-6">
    <div class="flex items-center justify-between p-4 border border-gray-200 dark:border-gray-700 rounded-lg">
      <div>
        <p class="font-medium text-gray-900 dark:text-white">Monthly</p>
        <p class="text-gray-600 dark:text-gray-400">$9/month</p>
      </div>
      <%= button_to "Subscribe", checkout_path(price_id: AppConfig::Stripe::PRICE_ID_MONTHLY),
        class: "px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700" %>
    </div>

    <div class="flex items-center justify-between p-4 border-2 border-indigo-500 rounded-lg">
      <div>
        <p class="font-medium text-gray-900 dark:text-white">Annual <span class="text-green-600 text-sm">(Save 17%)</span></p>
        <p class="text-gray-600 dark:text-gray-400">$89/year</p>
      </div>
      <%= button_to "Subscribe", checkout_path(price_id: AppConfig::Stripe::PRICE_ID_ANNUAL),
        class: "px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700" %>
    </div>
  </div>

  <ul class="text-gray-600 dark:text-gray-400 space-y-2">
    <li class="flex items-center">
      <svg class="w-5 h-5 text-green-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
      </svg>
      Unlimited episodes
    </li>
    <li class="flex items-center">
      <svg class="w-5 h-5 text-green-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
      </svg>
      50,000 characters per episode
    </li>
    <li class="flex items-center">
      <svg class="w-5 h-5 text-green-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
        <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
      </svg>
      No attribution in audio
    </li>
  </ul>
</div>
```

**Step 6: Run test to verify it passes**

Run: `bin/rails test test/controllers/billing_controller_test.rb`

Expected: PASS

**Step 7: Commit**

```bash
git add app/controllers/billing_controller.rb app/views/billing/ test/controllers/billing_controller_test.rb
git commit -m "feat: add BillingController with subscription management"
```

---

## Task 17: Create SendsUpgradeNudge Service

**Files:**
- Create: `app/services/sends_upgrade_nudge.rb`
- Create: `test/services/sends_upgrade_nudge_test.rb`
- Create: `app/mailers/billing_mailer.rb`
- Create: `app/views/billing_mailer/upgrade_nudge.html.erb`

**Step 1: Write the failing test**

Create `test/services/sends_upgrade_nudge_test.rb`:

```ruby
require "test_helper"

class SendsUpgradeNudgeTest < ActiveSupport::TestCase
  setup do
    @free_user = users(:free_user)
  end

  test "sends email to free user" do
    assert_enqueued_emails 1 do
      result = SendsUpgradeNudge.call(user: @free_user)
      assert result.success?
    end
  end

  test "creates sent_message record" do
    expected_type = "upgrade_nudge_#{Date.current.strftime('%Y_%m')}"

    assert_difference -> { @free_user.sent_messages.count }, 1 do
      SendsUpgradeNudge.call(user: @free_user)
    end

    assert @free_user.sent_messages.exists?(message_type: expected_type)
  end

  test "does not send if already sent this month" do
    message_type = "upgrade_nudge_#{Date.current.strftime('%Y_%m')}"
    @free_user.sent_messages.create!(message_type: message_type)

    assert_no_enqueued_emails do
      result = SendsUpgradeNudge.call(user: @free_user)
      refute result.success?
      assert_match(/Already sent/, result.error)
    end
  end

  test "does not send to premium user" do
    premium_user = users(:subscriber)

    assert_no_enqueued_emails do
      result = SendsUpgradeNudge.call(user: premium_user)
      refute result.success?
      assert_match(/Not a free user/, result.error)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/sends_upgrade_nudge_test.rb`

Expected: FAIL (service and mailer don't exist)

**Step 3: Create the mailer**

Create `app/mailers/billing_mailer.rb`:

```ruby
class BillingMailer < ApplicationMailer
  def upgrade_nudge(user)
    @user = user
    @billing_url = billing_url

    mail(
      to: user.email_address,
      subject: "Ready for more?"
    )
  end
end
```

**Step 4: Create the email view**

Create `app/views/billing_mailer/upgrade_nudge.html.erb`:

```erb
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .button { display: inline-block; padding: 12px 24px; background-color: #4F46E5; color: white; text-decoration: none; border-radius: 6px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>You've used your free episodes</h1>

    <p>You've hit your limit of 2 free episodes this month.</p>

    <p>Upgrade to Premium for:</p>
    <ul>
      <li><strong>Unlimited episodes</strong> every month</li>
      <li><strong>50,000 characters</strong> per episode (vs 15,000)</li>
      <li><strong>No attribution</strong> in your audio</li>
    </ul>

    <p>
      <a href="<%= @billing_url %>" class="button">Upgrade to Premium</a>
    </p>

    <p>Plans start at $9/month or $89/year (save 17%).</p>

    <p>Thanks for using Very Normal TTS!</p>
  </div>
</body>
</html>
```

**Step 5: Write the service**

Create `app/services/sends_upgrade_nudge.rb`:

```ruby
class SendsUpgradeNudge
  def self.call(user:)
    new(user:).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return Result.failure("Not a free user") unless user.free?
    return Result.failure("Already sent this month") if already_sent_this_month?

    BillingMailer.upgrade_nudge(user).deliver_later
    user.sent_messages.create!(message_type: message_type_for_month)

    Result.success
  end

  private

  attr_reader :user

  def already_sent_this_month?
    user.sent_messages.exists?(message_type: message_type_for_month)
  end

  def message_type_for_month
    "upgrade_nudge_#{Date.current.strftime('%Y_%m')}"
  end
end
```

**Step 6: Run test to verify it passes**

Run: `bin/rails test test/services/sends_upgrade_nudge_test.rb`

Expected: PASS

**Step 7: Commit**

```bash
git add app/services/sends_upgrade_nudge.rb app/mailers/billing_mailer.rb app/views/billing_mailer/ test/services/sends_upgrade_nudge_test.rb
git commit -m "feat: add SendsUpgradeNudge service and BillingMailer"
```

---

## Task 18: Integrate Upgrade Nudge with RecordEpisodeUsage

**Files:**
- Modify: `app/services/record_episode_usage.rb`
- Modify: `test/services/record_episode_usage_test.rb`

**Step 1: Add test for nudge trigger**

Add to `test/services/record_episode_usage_test.rb`:

```ruby
  test "sends upgrade nudge when free user hits limit" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 1
    )

    assert_enqueued_emails 1 do
      RecordEpisodeUsage.call(user: @free_user)
    end

    usage = EpisodeUsage.current_for(@free_user)
    assert_equal 2, usage.episode_count
  end

  test "does not send nudge if already at limit" do
    EpisodeUsage.create!(
      user: @free_user,
      period_start: Time.current.beginning_of_month.to_date,
      episode_count: 2
    )

    assert_no_enqueued_emails do
      RecordEpisodeUsage.call(user: @free_user)
    end
  end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/record_episode_usage_test.rb`

Expected: FAIL (nudge not sent)

**Step 3: Update the service**

Update `app/services/record_episode_usage.rb`:

```ruby
class RecordEpisodeUsage
  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    return unless user.free?

    usage = EpisodeUsage.current_for(user)
    usage.increment!

    if usage.episode_count == AppConfig::Tiers::FREE_MONTHLY_EPISODES
      SendsUpgradeNudge.call(user: user)
    end
  end

  private

  attr_reader :user
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/record_episode_usage_test.rb`

Expected: PASS

**Step 5: Commit**

```bash
git add app/services/record_episode_usage.rb test/services/record_episode_usage_test.rb
git commit -m "feat: trigger upgrade nudge when free user hits episode limit"
```

---

## Task 19: Run Full Test Suite and Fix Remaining Issues

**Step 1: Run full test suite**

Run: `bin/rails test`

Expected: Identify any failing tests from the tier → account_type migration

**Step 2: Fix any remaining test failures**

Common fixes needed:
- Update fixtures that still reference `tier:`
- Update any tests checking `user.tier`
- Ensure `premium_user` fixture is replaced with `subscriber` fixture

**Step 3: Commit fixes**

```bash
git add -A
git commit -m "fix: update remaining tests for account_type migration"
```

---

## Task 20: Update Deploy Configuration

**Files:**
- Modify: `config/deploy.yml`
- Modify: `.github/workflows/deploy.yml`

**Step 1: Update Kamal config**

Add to `config/deploy.yml` in the `env.secret` section:

```yaml
    - STRIPE_SECRET_KEY
    - STRIPE_PUBLISHABLE_KEY
    - STRIPE_WEBHOOK_SECRET
    - STRIPE_PRICE_ID_MONTHLY
    - STRIPE_PRICE_ID_ANNUAL
```

**Step 2: Update GitHub workflow**

Add to `.github/workflows/deploy.yml` in the "Fetch secrets" step:

```yaml
          echo "STRIPE_SECRET_KEY=$(gcloud secrets versions access latest --secret=stripe-secret-key)" >> $GITHUB_ENV
          echo "STRIPE_PUBLISHABLE_KEY=$(gcloud secrets versions access latest --secret=stripe-publishable-key)" >> $GITHUB_ENV
          echo "STRIPE_WEBHOOK_SECRET=$(gcloud secrets versions access latest --secret=stripe-webhook-secret)" >> $GITHUB_ENV
          echo "STRIPE_PRICE_ID_MONTHLY=$(gcloud secrets versions access latest --secret=stripe-price-id-monthly)" >> $GITHUB_ENV
          echo "STRIPE_PRICE_ID_ANNUAL=$(gcloud secrets versions access latest --secret=stripe-price-id-annual)" >> $GITHUB_ENV
```

Add to the "Write Kamal secrets" step:

```yaml
          STRIPE_SECRET_KEY=$STRIPE_SECRET_KEY
          STRIPE_PUBLISHABLE_KEY=$STRIPE_PUBLISHABLE_KEY
          STRIPE_WEBHOOK_SECRET=$STRIPE_WEBHOOK_SECRET
          STRIPE_PRICE_ID_MONTHLY=$STRIPE_PRICE_ID_MONTHLY
          STRIPE_PRICE_ID_ANNUAL=$STRIPE_PRICE_ID_ANNUAL
```

**Step 3: Commit**

```bash
git add config/deploy.yml .github/workflows/deploy.yml
git commit -m "chore: add Stripe secrets to deploy configuration"
```

---

## Verification Checklist

Before marking complete, verify:

- [ ] `bin/rails test` passes
- [ ] `bundle exec rubocop` passes
- [ ] Migrations run cleanly: `bin/rails db:migrate:reset`
- [ ] Server starts: `bin/rails server`
- [ ] Visit `/billing` as logged-in user
- [ ] Stripe CLI webhook forwarding works: `stripe listen --forward-to localhost:3000/webhooks/stripe`

---

**Plan complete and saved to `docs/plans/2025-12-31-stripe-billing-implementation.md`.**

To execute:
1. Open a new Claude session in a worktree
2. Use executing-plans skill to run the plan in batches
3. After each batch, bring the progress report back here for review
