require "test_helper"
require "rake"

class AccountsRakeTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("accounts:create_complimentary")
  end

  teardown do
    ENV.delete("EMAIL")
    Rake::Task["accounts:create_complimentary"].reenable
  end

  test "aborts when EMAIL is missing" do
    ENV.delete("EMAIL")

    error = assert_raises(SystemExit) do
      capture_io { Rake::Task["accounts:create_complimentary"].invoke }
    end
    assert_equal 1, error.status
  end

  test "aborts when EMAIL is invalid" do
    ENV["EMAIL"] = "not-an-email"

    error = assert_raises(SystemExit) do
      capture_io { Rake::Task["accounts:create_complimentary"].invoke }
    end
    assert_equal 1, error.status
  end

  test "creates new complimentary user and sends welcome email" do
    ENV["EMAIL"] = "newfriend@example.com"

    assert_enqueued_emails 1 do
      output, = capture_io { Rake::Task["accounts:create_complimentary"].invoke }

      assert_match "Created complimentary account for newfriend@example.com", output
      assert_match "Welcome email queued", output
      assert_match "Done!", output
    end

    user = User.find_by(email_address: "newfriend@example.com")
    assert user.present?, "User should have been created"
    assert user.complimentary?, "User should be complimentary"
    assert user.auth_token.present?, "Auth token should have been generated"
  end

  test "upgrades existing standard user to complimentary" do
    ENV["EMAIL"] = users(:one).email_address

    assert_enqueued_emails 1 do
      output, = capture_io { Rake::Task["accounts:create_complimentary"].invoke }

      assert_match "Upgraded", output
      assert_match "Welcome email queued", output
    end

    users(:one).reload
    assert users(:one).complimentary?, "User should be upgraded to complimentary"
  end

  test "handles already-complimentary user gracefully" do
    ENV["EMAIL"] = users(:complimentary_user).email_address

    assert_enqueued_emails 1 do
      output, = capture_io { Rake::Task["accounts:create_complimentary"].invoke }

      assert_match "already a complimentary account", output
      assert_match "Welcome email queued", output
    end
  end
end
