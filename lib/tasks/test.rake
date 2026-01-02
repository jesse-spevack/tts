# frozen_string_literal: true

namespace :test do
  desc "Purge E2E test users (emails ending in @test.example.com)"
  task purge_e2e_users: :environment do
    users = User.where("email_address LIKE ?", "%@test.example.com")
    count = users.count
    users.destroy_all
    puts "Deleted #{count} E2E test users"
  end
end
