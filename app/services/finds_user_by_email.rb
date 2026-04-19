# frozen_string_literal: true

# Looks up a user by email_address across every row, including soft-deleted.
# Soft-deleted users must stay reachable by email so the magic-link revive
# flow has something to bind to — and the DB unique index on email_address
# means we never want to CreateUser for an email that already exists. Always
# hits User.unscoped on purpose.
class FindsUserByEmail
  def self.call(email_address:)
    new(email_address: email_address).call
  end

  def initialize(email_address:)
    @email_address = email_address
  end

  def call
    User.unscoped.find_by(email_address: @email_address)
  end
end
