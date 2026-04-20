# One-off migration (agent-team-rbpr) for users who bought credits under
# the old $1/credit pricing before the pricing restructure shipped. Bumps
# each target user's balance per the formula new = (current * 2) + 20 and
# sends BillingMailer#legacy_pricing_migration_2026_04.
#
# Idempotent: a CreditTransaction with stripe_session_id
# "legacy_pricing_migration_2026_04_user_<id>" gates re-runs. Safe to run
# twice.
#
# Delete this file (and the mailer method + template) after the migration
# has run in prod.
namespace :pricing do
  desc "Bump legacy credit-holder balances + send the heads-up email (agent-team-rbpr)"
  task legacy_migration: :environment do
    dry_run = ENV["DRY_RUN"] == "1"
    only_email = ENV["ONLY_EMAIL"].presence

    users = if only_email
      User.where(email_address: only_email)
    else
      User.joins(:credit_balance)
          .where(credit_balances: { balance: 1.. })
          .where.not(account_type: [ :complimentary, :unlimited ])
    end

    puts "Target users: #{users.count}"
    puts "Mode: #{dry_run ? 'DRY RUN (no mutation)' : 'LIVE'}"
    puts "---"

    report = []
    users.find_each do |user|
      previous = user.credit_balance&.balance || 0
      # ONLY_EMAIL lets Jesse test on his own account, which may not have
      # a credit_balance row yet. Create one so the (0 * 2) + 20 bump has
      # somewhere to land.
      if previous.zero? && only_email
        CreditBalance.for(user)
        previous = 0
      end

      new_balance = (previous * 2) + 20
      bump_amount = new_balance - previous
      session_tag = "legacy_pricing_migration_2026_04_user_#{user.id}"

      if CreditTransaction.exists?(stripe_session_id: session_tag)
        puts "SKIP user=#{user.id} (#{user.email_address}) — already migrated"
        report << { user_id: user.id, email: user.email_address, status: :skipped_already_migrated }
        next
      end

      if dry_run
        puts "DRY: user=#{user.id} (#{user.email_address}) bump #{previous} -> #{new_balance} (+#{bump_amount})"
        report << { user_id: user.id, email: user.email_address, previous: previous, new: new_balance, status: :dry_run }
      else
        GrantsCredits.call(user: user, amount: bump_amount, stripe_session_id: session_tag)
        BillingMailer.legacy_pricing_migration_2026_04(
          user: user,
          previous_balance: previous,
          new_balance: new_balance
        ).deliver_later
        puts "LIVE: user=#{user.id} (#{user.email_address}) bumped #{previous} -> #{new_balance} (+#{bump_amount}); email queued"
        report << { user_id: user.id, email: user.email_address, previous: previous, new: new_balance, status: :migrated }
      end
    end

    puts "---"
    puts "Summary:"
    report.each do |r|
      puts "  user=#{r[:user_id]} email=#{r[:email]} status=#{r[:status]} previous=#{r[:previous]} new=#{r[:new]}"
    end
    puts "Total: #{report.count}"
  end
end
