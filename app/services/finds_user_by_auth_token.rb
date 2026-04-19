# frozen_string_literal: true

# Looks up a user by their magic-link raw token. Scans every user with an
# unexpired auth_token so VerifiesHashedToken runs in constant time across
# candidates — prevents timing attacks that could distinguish "token not
# found" from "token found but wrong". Returns the matching user or nil.
#
# Uses User.unscoped so soft-deleted users can still click their magic link
# and reach /restore_account. A before_action redirects soft-deleted users
# to the revive flow before they touch any other UI.
class FindsUserByAuthToken
  def self.call(raw_token:)
    new(raw_token: raw_token).call
  end

  def initialize(raw_token:)
    @raw_token = raw_token
  end

  def call
    return nil if @raw_token.blank?

    User.unscoped.with_valid_auth_token.find do |user|
      VerifiesHashedToken.call(hashed_token: user.auth_token, raw_token: @raw_token)
    end
  end
end
