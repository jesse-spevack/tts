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
