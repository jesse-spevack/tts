require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  teardown do
    Current.reset
  end

  test ".admin? returns false when no session" do
    Current.session = nil
    assert_not Current.admin?
  end

  test ".admin? returns false for non-admin user" do
    user = users(:one)
    Current.session = Session.create!(user: user)
    assert_not Current.admin?
  end

  test ".admin? returns true for admin user" do
    user = users(:admin_user)
    Current.session = Session.create!(user: user)
    assert Current.admin?
  end
end
