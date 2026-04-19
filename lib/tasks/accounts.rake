namespace :accounts do
  desc "Create or upgrade a complimentary account and send welcome email"
  task create_complimentary: :environment do
    email = ENV["EMAIL"]

    abort "ERROR: EMAIL is required. Usage: bin/rails accounts:create_complimentary EMAIL=friend@example.com" if email.blank?
    abort "ERROR: '#{email}' doesn't look like a valid email address." unless email.match?(URI::MailTo::EMAIL_REGEXP)

    # Unscoped so admin ops can touch soft-deleted accounts without tripping
    # the DB unique index when we would otherwise try to create a new row.
    user = User.unscoped.find_by(email_address: email)

    if user
      if user.complimentary?
        puts "#{email} is already a complimentary account. Sending a fresh login link..."
      else
        user.update!(account_type: :complimentary)
        puts "Upgraded #{email} to complimentary account."
      end
    else
      result = CreatesUser.call(email_address: email)
      abort "ERROR: Could not create user for #{email}." unless result.success?

      user = result.data[:user]
      user.update!(account_type: :complimentary)
      puts "Created complimentary account for #{email}."
    end

    token = GeneratesAuthToken.call(user: user)
    ComplimentaryMailer.welcome(user, token: token).deliver_later

    puts "Welcome email queued for #{email}."
    puts "Done!"
  end
end
