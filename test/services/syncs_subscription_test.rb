require "test_helper"

class SyncsSubscriptionTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = users(:free_user)
    Stripe.api_key = "sk_test_fake"
  end

  test "creates new subscription for active Stripe subscription" do
    @user.update!(stripe_customer_id: "cus_new")

    stub_stripe_subscription(
      id: "sub_new",
      customer: "cus_new",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    result = SyncsSubscription.call(stripe_subscription_id: "sub_new")

    assert result.success?
    subscription = result.data
    assert_equal @user, subscription.user
    assert subscription.active?
  end

  test "updates existing subscription" do
    @user.update!(stripe_customer_id: "cus_existing")
    subscription = Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_existing",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.week.from_now
    )

    stub_stripe_subscription(
      id: "sub_existing",
      customer: "cus_existing",
      status: "past_due",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    result = SyncsSubscription.call(stripe_subscription_id: "sub_existing")

    assert result.success?
    subscription.reload
    assert subscription.past_due?
  end

  test "sets canceled status for canceled subscription" do
    @user.update!(stripe_customer_id: "cus_canceled")

    stub_stripe_subscription(
      id: "sub_canceled",
      customer: "cus_canceled",
      status: "canceled",
      price_id: "price_monthly",
      current_period_end: 1.day.ago.to_i
    )

    result = SyncsSubscription.call(stripe_subscription_id: "sub_canceled")

    assert result.success?
    assert result.data.canceled?
  end

  test "maps trialing status to active" do
    @user.update!(stripe_customer_id: "cus_trial")

    stub_stripe_subscription(
      id: "sub_trial",
      customer: "cus_trial",
      status: "trialing",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    result = SyncsSubscription.call(stripe_subscription_id: "sub_trial")

    assert result.success?
    assert result.data.active?
  end

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

  test "sends cancellation email when subscription transitions to canceling" do
    @user.update!(stripe_customer_id: "cus_cancel_email")
    Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_cancel_email",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now,
      cancel_at: nil
    )

    stub_stripe_subscription(
      id: "sub_cancel_email",
      customer: "cus_cancel_email",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i,
      cancel_at_period_end: true
    )

    assert_enqueued_emails 1 do
      SyncsSubscription.call(stripe_subscription_id: "sub_cancel_email")
    end
  end

  test "does not send cancellation email when subscription was already canceling" do
    @user.update!(stripe_customer_id: "cus_already_canceling")
    Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_already_canceling",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now,
      cancel_at: 1.month.from_now
    )

    stub_stripe_subscription(
      id: "sub_already_canceling",
      customer: "cus_already_canceling",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i,
      cancel_at_period_end: true
    )

    assert_no_enqueued_emails do
      SyncsSubscription.call(stripe_subscription_id: "sub_already_canceling")
    end
  end

  test "does not send cancellation email for new subscription that is not canceling" do
    @user.update!(stripe_customer_id: "cus_new_active")

    stub_stripe_subscription(
      id: "sub_new_active",
      customer: "cus_new_active",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i,
      cancel_at_period_end: false
    )

    assert_no_enqueued_emails do
      SyncsSubscription.call(stripe_subscription_id: "sub_new_active")
    end
  end

  test "sends subscription ended email when active subscription transitions to canceled" do
    @user.update!(stripe_customer_id: "cus_ended")
    Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_ended",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.day.ago
    )

    stub_stripe_subscription(
      id: "sub_ended",
      customer: "cus_ended",
      status: "canceled",
      price_id: "price_monthly",
      current_period_end: 1.day.ago.to_i
    )

    assert_enqueued_emails 1 do
      SyncsSubscription.call(stripe_subscription_id: "sub_ended")
    end
  end

  test "does not send subscription ended email when subscription was already canceled" do
    @user.update!(stripe_customer_id: "cus_already_canceled")
    Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_already_canceled",
      stripe_price_id: "price_monthly",
      status: :canceled,
      current_period_end: 1.day.ago
    )

    stub_stripe_subscription(
      id: "sub_already_canceled",
      customer: "cus_already_canceled",
      status: "canceled",
      price_id: "price_monthly",
      current_period_end: 1.day.ago.to_i
    )

    assert_no_enqueued_emails do
      SyncsSubscription.call(stripe_subscription_id: "sub_already_canceled")
    end
  end

  test "sends subscription ended email when past_due subscription transitions to canceled" do
    @user.update!(stripe_customer_id: "cus_past_due_ended")
    Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_past_due_ended",
      stripe_price_id: "price_monthly",
      status: :past_due,
      current_period_end: 1.day.ago
    )

    stub_stripe_subscription(
      id: "sub_past_due_ended",
      customer: "cus_past_due_ended",
      status: "canceled",
      price_id: "price_monthly",
      current_period_end: 1.day.ago.to_i
    )

    assert_enqueued_emails 1 do
      SyncsSubscription.call(stripe_subscription_id: "sub_past_due_ended")
    end
  end

  test "sends only ended email when subscription is immediately canceled with cancel_at" do
    @user.update!(stripe_customer_id: "cus_immediate")
    Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_immediate",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.day.ago,
      cancel_at: nil
    )

    stub_stripe_subscription(
      id: "sub_immediate",
      customer: "cus_immediate",
      status: "canceled",
      price_id: "price_monthly",
      current_period_end: 1.day.ago.to_i,
      cancel_at: 1.day.ago.to_i
    )

    # Should send only the ended email, not both cancellation and ended
    assert_enqueued_emails 1 do
      SyncsSubscription.call(stripe_subscription_id: "sub_immediate")
    end
  end

  test "does not send subscription ended email for new subscription that starts canceled" do
    @user.update!(stripe_customer_id: "cus_new_canceled")

    stub_stripe_subscription(
      id: "sub_new_canceled",
      customer: "cus_new_canceled",
      status: "canceled",
      price_id: "price_monthly",
      current_period_end: 1.day.ago.to_i
    )

    assert_no_enqueued_emails do
      SyncsSubscription.call(stripe_subscription_id: "sub_new_canceled")
    end
  end

  test "persists cancel_at when SendsCancellationEmail raises RecordNotUnique" do
    @user.update!(stripe_customer_id: "cus_cancel_race")
    Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_cancel_race",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now,
      cancel_at: nil
    )

    stub_stripe_subscription(
      id: "sub_cancel_race",
      customer: "cus_cancel_race",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i,
      cancel_at_period_end: true
    )

    Mocktail.replace(SendsCancellationEmail)
    stubs { |m| SendsCancellationEmail.call(user: m.any, subscription: m.any, ends_at: m.any) }
      .with { raise ActiveRecord::RecordNotUnique.new("duplicate key") }

    begin
      SyncsSubscription.call(stripe_subscription_id: "sub_cancel_race")
    rescue ActiveRecord::RecordNotUnique
      # Pre-fix: exception bubbles out past the transaction rescue.
      # Post-fix: email service returns Result.failure and no exception escapes.
    end

    persisted = Subscription.find_by(stripe_subscription_id: "sub_cancel_race")
    assert_not_nil persisted.cancel_at,
      "Expected cancel_at to persist even when SendsCancellationEmail raises RecordNotUnique"
  end

  test "persists canceled status when SendsSubscriptionEndedEmail raises RecordNotUnique" do
    @user.update!(stripe_customer_id: "cus_ended_race")
    Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_ended_race",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.day.ago
    )

    stub_stripe_subscription(
      id: "sub_ended_race",
      customer: "cus_ended_race",
      status: "canceled",
      price_id: "price_monthly",
      current_period_end: 1.day.ago.to_i
    )

    Mocktail.replace(SendsSubscriptionEndedEmail)
    stubs { |m| SendsSubscriptionEndedEmail.call(user: m.any, subscription: m.any) }
      .with { raise ActiveRecord::RecordNotUnique.new("duplicate key") }

    begin
      SyncsSubscription.call(stripe_subscription_id: "sub_ended_race")
    rescue ActiveRecord::RecordNotUnique
      # See note on sibling test above.
    end

    persisted = Subscription.find_by(stripe_subscription_id: "sub_ended_race")
    assert persisted.canceled?,
      "Expected canceled status to persist even when SendsSubscriptionEndedEmail raises RecordNotUnique"
  end

  test "dispatches cancellation email after transaction commits" do
    @user.update!(stripe_customer_id: "cus_cancel_commit")
    Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_cancel_commit",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.month.from_now,
      cancel_at: nil
    )

    stub_stripe_subscription(
      id: "sub_cancel_commit",
      customer: "cus_cancel_commit",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i,
      cancel_at_period_end: true
    )

    # Transactional fixtures wrap every test in one transaction, so baseline
    # open_transactions == 1. If SyncsSubscription still wraps the email
    # dispatch in its own transaction, open_transactions will be >= 2 at the
    # moment the email service is called. Post-fix it must equal 1.
    observed_open_transactions = nil
    Mocktail.replace(SendsCancellationEmail)
    stubs { |m| SendsCancellationEmail.call(user: m.any, subscription: m.any, ends_at: m.any) }
      .with do
        observed_open_transactions = ActiveRecord::Base.connection.open_transactions
        Result.success
      end

    SyncsSubscription.call(stripe_subscription_id: "sub_cancel_commit")

    assert_equal 1, observed_open_transactions,
      "Expected SendsCancellationEmail to be invoked after SyncsSubscription's transaction committed"
  end

  test "dispatches subscription ended email after transaction commits" do
    @user.update!(stripe_customer_id: "cus_ended_commit")
    Subscription.create!(
      user: @user,
      stripe_subscription_id: "sub_ended_commit",
      stripe_price_id: "price_monthly",
      status: :active,
      current_period_end: 1.day.ago
    )

    stub_stripe_subscription(
      id: "sub_ended_commit",
      customer: "cus_ended_commit",
      status: "canceled",
      price_id: "price_monthly",
      current_period_end: 1.day.ago.to_i
    )

    observed_open_transactions = nil
    Mocktail.replace(SendsSubscriptionEndedEmail)
    stubs { |m| SendsSubscriptionEndedEmail.call(user: m.any, subscription: m.any) }
      .with do
        observed_open_transactions = ActiveRecord::Base.connection.open_transactions
        Result.success
      end

    SyncsSubscription.call(stripe_subscription_id: "sub_ended_commit")

    assert_equal 1, observed_open_transactions,
      "Expected SendsSubscriptionEndedEmail to be invoked after SyncsSubscription's transaction committed"
  end

  test "returns Result.failure and logs warn when customer lookup misses" do
    # Soft-deleted user (hidden by default_scope) or a Stripe customer we've
    # never seen. Controller-layer rescue used to swallow this as a blanket
    # RecordNotFound; now the lookup is narrow and explicit.
    stub_stripe_subscription(
      id: "sub_no_user",
      customer: "cus_unknown",
      status: "active",
      price_id: "price_monthly",
      current_period_end: 1.month.from_now.to_i
    )

    log_output = capture_logs do
      @result = SyncsSubscription.call(stripe_subscription_id: "sub_no_user")
    end

    assert_not @result.success?
    assert_match(/No user found for customer/, @result.error)
    assert_match(/event=syncs_subscription_user_not_found/, log_output)
    assert_match(/stripe_customer_id=cus_unknown/, log_output)
    assert_match(/reason=user_missing_or_soft_deleted/, log_output)
  end

  private

  def capture_logs
    original_logger = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original_logger
  end

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
end
