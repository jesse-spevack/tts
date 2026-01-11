# frozen_string_literal: true

require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with valid session cookie" do
    session = sessions(:one)
    cookies.signed[:session_id] = session.id

    connect

    assert_equal session.user, connection.current_user
  end

  test "rejects connection without session cookie" do
    assert_reject_connection { connect }
  end

  test "rejects connection with invalid session cookie" do
    cookies.signed[:session_id] = "invalid-session-id"

    assert_reject_connection { connect }
  end

  test "rejects connection with non-existent session id" do
    cookies.signed[:session_id] = 999_999

    assert_reject_connection { connect }
  end
end
