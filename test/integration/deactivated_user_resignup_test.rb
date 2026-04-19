# frozen_string_literal: true

require "test_helper"

# Proves the anonymize-in-place design: a deactivated user's email is
# rotated to a sentinel, so re-signup with the original email creates a
# brand-new User row. No default_scope, no .unscoped — just natural SQL.
class DeactivatedUserResignupTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  test "re-signup with original email after deactivation creates a fresh user" do
    user = users(:one)
    original_email = user.email_address
    original_id = user.id

    # Give the user at least one episode so we can assert it stays on the
    # original row (episodes are deleted async via DeleteEpisodeJob)
    assert user.episodes.any?

    DeactivatesUser.call(user: user)

    # The original row still exists, but the email is rotated
    user.reload
    assert_equal "deleted-#{original_id}@deleted.invalid", user.email_address
    assert user.deactivated?

    # POST to /session with the ORIGINAL email creates a new user via
    # SendsMagicLink -> CreatesUser (User.find_by returns nil because the
    # email was rotated, so a new record is created with that email)
    assert_difference -> { User.count }, 1 do
      post session_path, params: { email_address: original_email }
    end

    fresh = User.find_by(email_address: original_email)
    assert_not_nil fresh
    assert_not_equal original_id, fresh.id
    assert fresh.active
    assert_not fresh.deactivated?
    assert_empty fresh.episodes

    # Original row still exists with rotated email
    original = User.find(original_id)
    assert_equal "deleted-#{original_id}@deleted.invalid", original.email_address
    assert original.deactivated?
  end
end
